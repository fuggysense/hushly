import { useCallback, useEffect, useRef, useState } from 'react';
import { Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
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
import { Pill } from '@/components/Pill';
import { StatusEyebrow } from '@/components/StatusEyebrow';
import { TranscriptCard } from '@/components/TranscriptCard';
import { Waveform } from '@/components/Waveform';
import { useAuth } from '@/lib/auth';
import { signOut } from '@/lib/clientAuth';
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
        finalizeAndCopy(rawText, durationMs, { polish: settings.polishWithGPT }),
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
  }, [recorder, elapsedMs, settings.polishWithGPT]);

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

  const finalizingLabel = settings.polishWithGPT ? 'Cleaning…' : 'Transcribing…';
  const status: { label: string; tone: StatusTone } =
    phase === 'recording'
      ? { label: `Recording ${formatMs(elapsedMs)}`, tone: 'live' }
      : phase === 'finalizing'
        ? { label: finalizingLabel, tone: 'work' }
        : phase === 'done'
          ? { label: 'Copied', tone: 'ok' }
          : phase === 'error'
            ? { label: 'Error', tone: 'err' }
            : { label: 'Ready', tone: 'idle' };

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
          <Link href="/(app)/usage" style={styles.headerLink}>
            Usage
          </Link>
          <Link href="/(app)/admin" style={styles.headerLink}>
            Admin
          </Link>
          <Pressable
            onPress={() => signOut()}
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
        <ScrollView contentContainerStyle={styles.mainContent} showsVerticalScrollIndicator={false}>
          <View style={styles.recordStage}>
            <StatusEyebrow label={status.label} tone={status.tone} />

            <View style={styles.pillWrap}>
              {phase === 'recording' ? (
                <Animated.View style={[styles.pulseRing, pulseStyle]} pointerEvents="none" />
              ) : null}

              {phase === 'recording' ? (
                <Pill
                  left={
                    <Pressable
                      onPress={cancel}
                      accessibilityRole="button"
                      accessibilityLabel="Cancel recording"
                      hitSlop={10}
                      style={({ pressed }) => [styles.pillIconButton, pressed && styles.btnPressed]}
                    >
                      <Text style={styles.pillGlyph}>×</Text>
                    </Pressable>
                  }
                  center={<Waveform active />}
                  right={
                    <Pressable
                      onPress={stop}
                      accessibilityRole="button"
                      accessibilityLabel="Stop recording and transcribe"
                      hitSlop={10}
                      style={({ pressed }) => [styles.pillIconButton, pressed && styles.btnPressed]}
                    >
                      <Text style={styles.pillGlyph}>✓</Text>
                    </Pressable>
                  }
                />
              ) : (
                <Pressable
                  onPress={toggle}
                  disabled={phase === 'finalizing'}
                  accessibilityRole="button"
                  accessibilityLabel={
                    phase === 'finalizing'
                      ? 'Transcribing and cleaning'
                      : phase === 'done'
                        ? 'Start a new recording'
                        : settings.label
                  }
                  accessibilityState={{ disabled: phase === 'finalizing' }}
                  style={({ pressed }) => [
                    styles.pillPressable,
                    pressed && styles.btnPressed,
                    phase === 'finalizing' && styles.btnBusy,
                  ]}
                >
                  <Pill center={<Waveform active={false} />} />
                </Pressable>
              )}
            </View>

            {phase === 'recording' ? (
              <Text style={styles.pillHint}>
                Tap ✓ to transcribe · × to discard{isWeb ? ' · Esc cancels' : ''}
              </Text>
            ) : phase === 'finalizing' ? (
              <Text style={styles.pillHint}>
                {settings.polishWithGPT ? 'Transcribing + cleaning…' : 'Transcribing…'}
              </Text>
            ) : isWeb ? (
              <View style={styles.inlineHint}>
                <Text style={styles.idleHint}>Press</Text>
                <View style={styles.kbd}>
                  <Text style={styles.kbdText}>{shortcutLabel}</Text>
                </View>
                <Text style={styles.idleHint}>or tap waveform to start</Text>
              </View>
            ) : (
              <Text style={styles.idleHint}>Tap waveform to start dictating</Text>
            )}
          </View>

          {cleaned ? (
            <Animated.View entering={FadeIn.duration(220)} style={styles.transcriptReveal}>
              <TranscriptCard>
                <Text style={styles.eyebrow}>Cleaned · copied</Text>
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
              </TranscriptCard>
            </Animated.View>
          ) : null}

          {errMsg ? (
            <View style={styles.errRow}>
              <View style={styles.errDot} />
              <Text style={styles.errText}>{errMsg}</Text>
            </View>
          ) : null}
        </ScrollView>
      </View>

      <View style={styles.footer}>
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
            <>
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
              <Pressable
                onPress={() =>
                  saveSettings({ ...settings, polishWithGPT: !settings.polishWithGPT })
                }
                accessibilityRole="switch"
                accessibilityState={{ checked: settings.polishWithGPT }}
                accessibilityLabel={
                  settings.polishWithGPT
                    ? 'Disable GPT polish — transcript will use raw Deepgram output'
                    : 'Enable GPT polish — transcript will be cleaned by AI'
                }
                hitSlop={8}
              >
                <Text style={styles.editLink}>
                  Polish: {settings.polishWithGPT ? 'On' : 'Off'}
                </Text>
              </Pressable>
            </>
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
    fontFamily: 'Inter-Light',
    fontSize: 22,
    letterSpacing: -0.4,
  },
  headerRight: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  headerLink: {
    color: C.textSecondary,
    fontFamily: 'Inter-Medium',
    fontSize: 13,
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
    fontFamily: 'JetBrainsMono-Medium',
    textAlign: 'center',
    lineHeight: 22,
    fontSize: 11,
    overflow: 'hidden',
  },
  signOut: { color: C.textSecondary, fontFamily: 'Inter-Medium', fontSize: 12 },
  hairline: { height: 1, backgroundColor: C.hairline, marginHorizontal: 16 },

  middle: { flex: 1 },
  mainContent: {
    flexGrow: 1,
    paddingHorizontal: 16,
    paddingTop: 46,
    paddingBottom: 28,
    alignItems: 'center',
  },
  recordStage: { width: '100%', alignItems: 'center', gap: 16, paddingVertical: 24 },
  pillWrap: {
    width: '100%',
    minHeight: 82,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pillPressable: { width: '100%', alignItems: 'center' },
  pillIconButton: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pillGlyph: {
    color: C.textPrimary,
    fontFamily: 'Inter-Light',
    fontSize: 26,
    lineHeight: 30,
  },
  pillHint: {
    color: C.textTertiary,
    fontFamily: 'JetBrainsMono-Regular',
    fontSize: 11,
    letterSpacing: 0.55,
    textAlign: 'center',
    textTransform: 'uppercase',
  },
  transcriptReveal: { width: '100%', maxWidth: 680, marginTop: 10 },
  eyebrow: {
    color: C.textTertiary,
    fontFamily: 'JetBrainsMono-Regular',
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 1.2,
    marginBottom: 8,
  },
  eyebrowSpaced: { marginTop: 24 },
  cleaned: { color: C.textPrimary, fontFamily: 'Inter-Regular', fontSize: 19, lineHeight: 28 },
  partial: { color: C.textSecondary, fontFamily: 'Inter-Regular', fontSize: 16, lineHeight: 26 },

  idleHint: { color: C.textTertiary, fontFamily: 'Inter-Regular', fontSize: 15, textAlign: 'center' },
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
    fontFamily: 'JetBrainsMono-Medium',
    fontSize: 12,
    fontVariant: ['tabular-nums'],
  },
  errRow: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 16 },
  errDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: C.accent },
  errText: { color: C.accent, fontFamily: 'Inter-Regular', fontSize: 13, flex: 1 },

  pulseRing: {
    position: 'absolute',
    width: 304,
    height: 82,
    borderRadius: 41,
    backgroundColor: C.accent,
  },

  footer: { alignItems: 'center', paddingHorizontal: 24, paddingTop: 6 },
  btnBusy: { opacity: 0.85 },
  btnPressed: { transform: [{ scale: 0.985 }], opacity: 0.92 },

  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    minHeight: 24,
    marginTop: 2,
  },
  editLink: { color: C.textMuted, fontFamily: 'JetBrainsMono-Regular', fontSize: 12 },
  editSave: { color: C.accent, fontFamily: 'Inter-Medium', fontSize: 13 },
  labelInput: {
    color: C.textPrimary,
    backgroundColor: C.elevated,
    borderWidth: 1,
    borderColor: C.hairline,
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 8,
    minWidth: 180,
    fontFamily: 'Inter-Regular',
    fontSize: 14,
  },
});
