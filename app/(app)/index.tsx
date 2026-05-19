import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import Animated, {
  cancelAnimation,
  Easing,
  FadeIn,
  useAnimatedStyle,
  useSharedValue,
  withRepeat,
  withTiming,
} from 'react-native-reanimated';
import * as Haptics from 'expo-haptics';
import {
  RecordingPresets,
  requestRecordingPermissionsAsync,
  setAudioModeAsync,
  useAudioRecorder,
} from 'expo-audio';
import { File } from 'expo-file-system';
import { Link } from 'expo-router';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { finalizeAndCopy, persistTranscript, transcribe, uploadAudio } from '@/lib/api';
import { useButtonSettings } from '@/lib/settings';
import { C } from '@/lib/tokens';

type Phase = 'idle' | 'recording' | 'finalizing' | 'done' | 'error';
type StatusTone = 'idle' | 'live' | 'work' | 'ok' | 'err';

export default function Home() {
  const { session } = useAuth();
  const [settings, saveSettings] = useButtonSettings();
  const [editingLabel, setEditingLabel] = useState(false);
  const [labelDraft, setLabelDraft] = useState('');

  const [phase, setPhase] = useState<Phase>('idle');
  const [cleaned, setCleaned] = useState('');
  const [raw, setRaw] = useState('');
  const [errMsg, setErrMsg] = useState('');
  const [elapsedMs, setElapsedMs] = useState(0);

  const startTimeRef = useRef(0);
  const elapsedTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const recorder = useAudioRecorder(RecordingPresets.HIGH_QUALITY);

  const webRecRef = useRef<{
    stop: () => Promise<{ blob: Blob; mimeType: string }>;
    cancel: () => Promise<void>;
  } | null>(null);

  // Pulse ring around the Stop button while recording. Single shared value
  // animates 0 -> 1 on a 1.4s loop; scale + opacity derive from it.
  const pulse = useSharedValue(0);
  useEffect(() => {
    if (phase === 'recording') {
      pulse.value = withRepeat(
        withTiming(1, { duration: 1400, easing: Easing.out(Easing.cubic) }),
        -1,
        false
      );
    } else {
      cancelAnimation(pulse);
      pulse.value = withTiming(0, { duration: 160 });
    }
  }, [phase, pulse]);

  const pulseStyle = useAnimatedStyle(() => ({
    transform: [{ scale: 1 + pulse.value * 0.22 }],
    opacity: 0.55 * (1 - pulse.value),
  }));

  useEffect(() => {
    if (Platform.OS !== 'web') {
      requestRecordingPermissionsAsync().catch(() => {});
      setAudioModeAsync({ playsInSilentMode: true, allowsRecording: true }).catch(() => {});
    }
    return () => {
      if (elapsedTimerRef.current) clearInterval(elapsedTimerRef.current);
    };
  }, []);

  useEffect(() => {
    if (Platform.OS !== 'web' || typeof window === 'undefined') return;
    const handler = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      if (e.key === settings.shortcutKey) {
        e.preventDefault();
        toggle();
      } else if (e.key === 'Escape' && phase === 'recording') {
        e.preventDefault();
        cancel();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [settings.shortcutKey, phase]);

  const startElapsed = () => {
    startTimeRef.current = Date.now();
    setElapsedMs(0);
    elapsedTimerRef.current = setInterval(() => {
      setElapsedMs(Date.now() - startTimeRef.current);
    }, 100);
  };

  const stopElapsed = () => {
    if (elapsedTimerRef.current) {
      clearInterval(elapsedTimerRef.current);
      elapsedTimerRef.current = null;
    }
  };

  const haptic = (kind: 'tap' | 'success' | 'warn') => {
    if (Platform.OS === 'web') return;
    try {
      if (kind === 'tap') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      else if (kind === 'success')
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      else Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
    } catch {
      /* haptics unavailable */
    }
  };

  const start = useCallback(async () => {
    setCleaned('');
    setRaw('');
    setErrMsg('');

    try {
      if (Platform.OS === 'web') {
        const mod = await import('@/lib/recorder.web');
        const rec = await mod.createRecorder();
        webRecRef.current = rec;
        await rec.start();
      } else {
        const perm = await requestRecordingPermissionsAsync();
        if (!perm.granted) {
          setErrMsg('Microphone permission denied');
          setPhase('error');
          haptic('warn');
          return;
        }
        await recorder.prepareToRecordAsync();
        recorder.record();
      }
      haptic('tap');
      setPhase('recording');
      startElapsed();
    } catch (e) {
      setErrMsg(e instanceof Error ? e.message : String(e));
      setPhase('error');
      stopElapsed();
      haptic('warn');
    }
  }, [recorder]);

  const stop = useCallback(async () => {
    const stopTapAt = Date.now();
    haptic('tap');
    stopElapsed();
    setPhase('finalizing');
    try {
      let audioBlob: Blob | null = null;
      let mimeType = 'audio/m4a';
      let durationMs = elapsedMs;

      if (Platform.OS === 'web') {
        const r = await webRecRef.current?.stop();
        webRecRef.current = null;
        if (r) {
          audioBlob = r.blob;
          mimeType = r.mimeType;
        }
        durationMs = Date.now() - startTimeRef.current;
      } else {
        try {
          await recorder.stop();
        } catch {
          /* */
        }
        durationMs = Date.now() - startTimeRef.current;
        const uri = recorder.uri;
        if (uri) {
          const buf = await new File(uri).arrayBuffer();
          audioBlob = new Blob([buf], { type: 'audio/m4a' });
          mimeType = 'audio/m4a';
        }
      }

      if (!audioBlob || audioBlob.size === 0) {
        setPhase('error');
        setErrMsg('No audio captured');
        haptic('warn');
        return;
      }

      const rawText = await transcribe(audioBlob, mimeType);
      setRaw(rawText);
      if (!rawText) {
        setPhase('error');
        setErrMsg('No speech detected');
        haptic('warn');
        return;
      }

      const [cleanResult, upload] = await Promise.all([
        finalizeAndCopy(rawText, durationMs),
        uploadAudio(audioBlob, mimeType),
      ]);
      setCleaned(cleanResult.cleaned);

      persistTranscript({
        raw: rawText,
        cleaned: cleanResult.cleaned,
        duration_ms: durationMs,
        audio_path: upload?.path,
        audio_mime: mimeType,
      }).catch(() => {});

      setPhase('done');
      haptic('success');
      if (typeof globalThis !== 'undefined') {
        (globalThis as unknown as { __hushlyFinalizeMs?: number }).__hushlyFinalizeMs =
          Date.now() - stopTapAt;
      }
    } catch (e) {
      setPhase('error');
      setErrMsg(e instanceof Error ? e.message : String(e));
      haptic('warn');
    }
  }, [recorder, elapsedMs]);

  const cancel = useCallback(async () => {
    haptic('tap');
    stopElapsed();
    try {
      if (Platform.OS === 'web') {
        await webRecRef.current?.cancel();
        webRecRef.current = null;
      } else {
        try {
          await recorder.stop();
        } catch {
          /* */
        }
      }
    } catch {
      /* */
    }
    setPhase('idle');
    setRaw('');
    setCleaned('');
    setErrMsg('');
  }, [recorder]);

  const toggle = () => {
    if (phase === 'recording') {
      stop();
    } else if (phase === 'idle' || phase === 'done' || phase === 'error') {
      start();
    }
  };

  const onLabelSave = async () => {
    const trimmed = labelDraft.trim();
    if (trimmed) await saveSettings({ ...settings, label: trimmed });
    setEditingLabel(false);
  };

  const email = session?.user.email ?? '';
  const isWeb = Platform.OS === 'web';
  const shortcutLabel =
    settings.shortcutKey === ' ' ? 'Space' : settings.shortcutKey.toUpperCase();

  const status: { dotColor: string; label: string; tone: StatusTone } =
    phase === 'recording'
      ? { dotColor: C.accent, label: `Recording  ${formatMs(elapsedMs)}`, tone: 'live' }
      : phase === 'finalizing'
        ? { dotColor: C.accent, label: 'Transcribing + cleaning', tone: 'work' }
        : phase === 'done'
          ? { dotColor: C.success, label: 'Copied to clipboard', tone: 'ok' }
          : phase === 'error'
            ? { dotColor: C.accent, label: 'Error', tone: 'err' }
            : { dotColor: C.textMuted, label: 'Ready', tone: 'idle' };

  return (
    <View style={styles.wrap}>
      <View style={styles.header}>
        <Text style={styles.brand} accessibilityRole="header">
          hushly
        </Text>
        <View style={styles.headerRight}>
          <Link href="/(app)/history" style={styles.headerLink}>
            History
          </Link>
          <Pressable
            onPress={() => supabase.auth.signOut()}
            accessibilityRole="button"
            accessibilityLabel={`Sign out ${email}`}
            style={styles.accountChip}
          >
            <Text style={styles.accountInitial}>{(email[0] || '·').toUpperCase()}</Text>
            <Text style={styles.signOut} numberOfLines={1}>
              Sign out
            </Text>
          </Pressable>
        </View>
      </View>
      <View style={styles.hairline} />

      <View style={styles.middle}>
        <ScrollView
          style={styles.transcriptBox}
          contentContainerStyle={styles.transcriptContent}
          showsVerticalScrollIndicator={false}
        >
          {cleaned ? (
            <Animated.View entering={FadeIn.duration(220)}>
              <Text style={styles.eyebrow}>Cleaned · copied to clipboard</Text>
              <Text style={styles.cleaned} selectable>
                {cleaned}
              </Text>
              {raw && raw !== cleaned ? (
                <>
                  <Text style={[styles.eyebrow, styles.eyebrowSpaced]}>Raw</Text>
                  <Text style={styles.partial} selectable>
                    {raw}
                  </Text>
                </>
              ) : null}
            </Animated.View>
          ) : phase === 'recording' ? (
            <View style={styles.centerState}>
              <Text style={styles.recTimer}>{formatMs(elapsedMs)}</Text>
              <Text style={styles.recHint}>
                Tap Stop to transcribe · Cancel to discard
                {isWeb ? ' · Esc to cancel' : ''}
              </Text>
            </View>
          ) : phase === 'finalizing' ? (
            <View style={styles.centerState}>
              <ActivityIndicator color={C.accent} />
              <Text style={styles.workingHint}>Transcribing + cleaning…</Text>
            </View>
          ) : (
            <View style={styles.centerState}>
              <View style={styles.glyphCircle}>
                <View style={styles.glyphDot} />
              </View>
              {isWeb ? (
                <View style={styles.inlineHint}>
                  <Text style={styles.idleHint}>Press</Text>
                  <View style={styles.kbd}>
                    <Text style={styles.kbdText}>{shortcutLabel}</Text>
                  </View>
                  <Text style={styles.idleHint}>or tap below to start dictating</Text>
                </View>
              ) : (
                <Text style={styles.idleHint}>Tap below to start dictating</Text>
              )}
            </View>
          )}
          {errMsg ? (
            <View style={styles.errRow}>
              <View style={styles.errDot} />
              <Text style={styles.errText}>{errMsg}</Text>
            </View>
          ) : null}
        </ScrollView>
      </View>

      <View style={styles.footer}>
        <View
          style={[
            styles.statusPill,
            status.tone === 'live' && styles.statusPillLive,
            status.tone === 'work' && styles.statusPillWork,
            status.tone === 'ok' && styles.statusPillOk,
            status.tone === 'err' && styles.statusPillErr,
          ]}
        >
          <View style={[styles.statusDot, { backgroundColor: status.dotColor }]} />
          <Text style={styles.statusText}>{status.label}</Text>
        </View>

        {phase === 'recording' ? (
          <View style={styles.btnRow}>
            <Pressable
              onPress={cancel}
              accessibilityRole="button"
              accessibilityLabel="Cancel recording"
              style={({ pressed }) => [styles.btnSecondary, pressed && styles.btnPressed]}
            >
              <Text style={styles.btnSecondaryText}>Cancel</Text>
            </Pressable>
            <View style={styles.recordWrap}>
              <Animated.View style={[styles.pulseRing, pulseStyle]} pointerEvents="none" />
              <Pressable
                onPress={stop}
                accessibilityRole="button"
                accessibilityLabel="Stop recording and transcribe"
                style={({ pressed }) => [
                  styles.btn,
                  styles.btnStop,
                  pressed && styles.btnPressed,
                ]}
              >
                <View style={styles.btnHighlight} pointerEvents="none" />
                <Text style={styles.btnText}>Stop</Text>
              </Pressable>
            </View>
          </View>
        ) : (
          <Pressable
            onPress={toggle}
            disabled={phase === 'finalizing'}
            accessibilityRole="button"
            accessibilityLabel={
              phase === 'finalizing'
                ? 'Transcribing'
                : phase === 'done'
                  ? 'Start a new recording'
                  : 'Start recording'
            }
            accessibilityState={{ disabled: phase === 'finalizing' }}
            style={({ pressed }) => [
              styles.btn,
              styles.btnPrimary,
              pressed && styles.btnPressed,
              phase === 'finalizing' && styles.btnBusy,
            ]}
          >
            <View style={styles.btnHighlight} pointerEvents="none" />
            {phase === 'finalizing' ? (
              <ActivityIndicator color={C.textPrimary} />
            ) : (
              <Text style={styles.btnText}>{settings.label}</Text>
            )}
          </Pressable>
        )}

        <View style={styles.metaRow}>
          {editingLabel ? (
            <>
              <TextInput
                style={styles.labelInput}
                value={labelDraft}
                onChangeText={setLabelDraft}
                autoFocus
                onSubmitEditing={onLabelSave}
                placeholderTextColor={C.textMuted}
              />
              <Pressable onPress={onLabelSave} accessibilityRole="button">
                <Text style={styles.editSave}>Save</Text>
              </Pressable>
            </>
          ) : (
            <Pressable
              onPress={() => {
                setLabelDraft(settings.label);
                setEditingLabel(true);
              }}
              accessibilityRole="button"
              accessibilityLabel="Edit button label"
              hitSlop={8}
            >
              <Text style={styles.editLink}>Customize button</Text>
            </Pressable>
          )}
        </View>
      </View>
    </View>
  );
}

function formatMs(ms: number) {
  const s = Math.floor(ms / 1000);
  const tenths = Math.floor((ms % 1000) / 100);
  return `${s}.${tenths}s`;
}

const styles = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: C.bg, paddingTop: 60, paddingBottom: 40 },

  header: {
    paddingHorizontal: 24,
    paddingBottom: 16,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  brand: {
    color: C.textPrimary,
    fontSize: 22,
    fontWeight: '700',
    letterSpacing: -0.4,
  },
  headerRight: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  headerLink: {
    color: C.textSecondary,
    fontSize: 13,
    fontWeight: '500',
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  accountChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: C.elevated,
    paddingLeft: 4,
    paddingRight: 12,
    paddingVertical: 4,
    borderRadius: 999,
    maxWidth: 160,
  },
  accountInitial: {
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: C.hairline,
    color: C.textPrimary,
    textAlign: 'center',
    lineHeight: 22,
    fontSize: 11,
    fontWeight: '600',
    overflow: 'hidden',
  },
  signOut: { color: C.textSecondary, fontSize: 12, fontWeight: '500' },
  hairline: { height: 1, backgroundColor: C.hairline, marginHorizontal: 16 },

  middle: { flex: 1, paddingHorizontal: 16, paddingTop: 16 },
  transcriptBox: {
    flex: 1,
    backgroundColor: C.surface,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: C.hairline,
  },
  transcriptContent: { padding: 20, paddingBottom: 32, flexGrow: 1 },
  eyebrow: {
    color: C.textTertiary,
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 1.2,
    marginBottom: 8,
    fontWeight: '600',
  },
  eyebrowSpaced: { marginTop: 24 },
  cleaned: { color: C.textPrimary, fontSize: 19, lineHeight: 28 },
  partial: { color: C.textSecondary, fontSize: 16, lineHeight: 26 },

  centerState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    paddingVertical: 32,
  },
  glyphCircle: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: C.elevated,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 4,
  },
  glyphDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: C.textMuted,
  },
  idleHint: { color: C.textTertiary, fontSize: 15, textAlign: 'center' },
  inlineHint: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    flexWrap: 'wrap',
    justifyContent: 'center',
  },
  kbd: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
    backgroundColor: C.elevated,
    borderWidth: 1,
    borderColor: C.hairline,
    borderBottomWidth: 2,
  },
  kbdText: {
    color: C.textSecondary,
    fontSize: 12,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  recTimer: {
    color: C.accent,
    fontSize: 44,
    fontWeight: '700',
    fontVariant: ['tabular-nums'],
    letterSpacing: -1,
  },
  recHint: { color: C.textTertiary, fontSize: 13, textAlign: 'center' },
  workingHint: { color: C.textSecondary, fontSize: 15, marginTop: 6 },

  errRow: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 16 },
  errDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: C.accent },
  errText: { color: C.accent, fontSize: 13, flex: 1 },

  footer: { alignItems: 'center', gap: 14, paddingHorizontal: 24, paddingTop: 16 },

  statusPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 999,
    backgroundColor: C.elevated,
    borderWidth: 1,
    borderColor: C.hairline,
  },
  statusPillLive: { backgroundColor: C.accentSoft, borderColor: 'transparent' },
  statusPillWork: { backgroundColor: C.accentSoft, borderColor: 'transparent' },
  statusPillOk: { backgroundColor: C.successSoft, borderColor: 'transparent' },
  statusPillErr: { backgroundColor: C.accentSoft, borderColor: 'transparent' },
  statusDot: { width: 6, height: 6, borderRadius: 3 },
  statusText: {
    color: C.textSecondary,
    fontSize: 12,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },

  recordWrap: { alignItems: 'center', justifyContent: 'center' },
  pulseRing: {
    position: 'absolute',
    width: 200,
    height: 88,
    borderRadius: 44,
    backgroundColor: C.accent,
  },

  btn: {
    height: 76,
    borderRadius: 38,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
  },
  btnPrimary: { width: 264, backgroundColor: C.accent },
  btnStop: { width: 168, backgroundColor: C.accent },
  btnSecondary: {
    height: 76,
    width: 108,
    borderRadius: 38,
    backgroundColor: C.elevated,
    borderWidth: 1,
    borderColor: C.hairline,
    alignItems: 'center',
    justifyContent: 'center',
  },
  btnBusy: { opacity: 0.85 },
  btnPressed: { transform: [{ scale: 0.985 }], opacity: 0.92 },
  btnHighlight: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: '50%',
    backgroundColor: C.hairline,
  },
  btnText: { color: C.textPrimary, fontSize: 17, fontWeight: '600', letterSpacing: -0.1 },
  btnSecondaryText: { color: C.textPrimary, fontSize: 15, fontWeight: '500' },
  btnRow: { flexDirection: 'row', gap: 12, alignItems: 'center' },

  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    minHeight: 24,
    marginTop: 2,
  },
  editLink: { color: C.textMuted, fontSize: 12, fontWeight: '500' },
  editSave: { color: C.accent, fontSize: 13, fontWeight: '600' },
  labelInput: {
    color: C.textPrimary,
    backgroundColor: C.elevated,
    borderWidth: 1,
    borderColor: C.hairline,
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 8,
    minWidth: 180,
    fontSize: 14,
  },
});
