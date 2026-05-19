import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
  Platform,
} from 'react-native';
import * as Clipboard from 'expo-clipboard';
import { Link } from 'expo-router';
import { TranscriptCard } from '@/components/TranscriptCard';
import { listTranscripts, deleteTranscript, retryTranscript } from '@/lib/api';
import { C } from '@/lib/tokens';

type Row = {
  id: string;
  cleaned_text: string;
  raw_text: string;
  created_at: string;
  duration_ms: number | null;
  audio_path: string | null;
};

export default function History() {
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const data = await listTranscripts();
    setRows(data);
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const onCopy = async (row: Row) => {
    await Clipboard.setStringAsync(row.cleaned_text);
    Alert.alert('Copied', 'Cleaned text copied to clipboard.');
  };

  const onRetry = async (row: Row) => {
    if (!row.audio_path) {
      Alert.alert(
        'No audio',
        'This transcript was created before audio storage. Cannot re-transcribe.'
      );
      return;
    }
    setBusyId(row.id);
    const result = await retryTranscript(row.id);
    setBusyId(null);
    if (!result) {
      Alert.alert('Retry failed', 'Could not re-transcribe. Check your connection.');
      return;
    }
    setRows((prev) =>
      prev.map((r) =>
        r.id === row.id ? { ...r, raw_text: result.raw, cleaned_text: result.cleaned } : r
      )
    );
  };

  const onDelete = (row: Row) => {
    const doDelete = async () => {
      setBusyId(row.id);
      const ok = await deleteTranscript(row.id, row.audio_path);
      setBusyId(null);
      if (ok) {
        setRows((prev) => prev.filter((r) => r.id !== row.id));
      } else {
        Alert.alert('Delete failed');
      }
    };
    if (Platform.OS === 'web') {
      if (typeof window !== 'undefined' && window.confirm('Delete this transcript?')) doDelete();
    } else {
      Alert.alert('Delete transcript?', 'This cannot be undone.', [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: doDelete },
      ]);
    }
  };

  return (
    <View style={styles.wrap}>
      <View style={styles.header}>
        <Link href="/(app)" style={styles.back}>
          ← back
        </Link>
        <Text style={styles.title}>History</Text>
        <View style={{ width: 48 }} />
      </View>

      {loading && rows.length === 0 ? (
        <View style={styles.empty}>
          <ActivityIndicator color={C.textTertiary} />
        </View>
      ) : rows.length === 0 ? (
        <View style={styles.empty}>
          <Text style={styles.emptyText}>No recordings yet.</Text>
          <Link href="/(app)" style={styles.emptyLink}>
            Start dictating →
          </Link>
        </View>
      ) : (
        <FlatList
          data={rows}
          keyExtractor={(r) => r.id}
          contentContainerStyle={{ padding: 16, gap: 12 }}
          refreshControl={<RefreshControl refreshing={loading} onRefresh={load} tintColor={C.textTertiary} />}
          renderItem={({ item }) => (
            <TranscriptCard style={styles.row}>
              <Text style={styles.timestamp}>
                {formatDate(item.created_at)}
                {item.duration_ms ? ` · ${(item.duration_ms / 1000).toFixed(1)}s` : ''}
                {!item.audio_path ? ' · no audio' : ''}
              </Text>
              <Text style={styles.preview} numberOfLines={4} selectable>
                {item.cleaned_text || item.raw_text || '(empty)'}
              </Text>
              <View style={styles.actions}>
                <Pressable style={styles.actionBtn} onPress={() => onCopy(item)} disabled={busyId === item.id}>
                  <Text style={styles.actionText}>Copy</Text>
                </Pressable>
                <Pressable
                  style={[styles.actionBtn, !item.audio_path && styles.actionDisabled]}
                  onPress={() => onRetry(item)}
                  disabled={busyId === item.id || !item.audio_path}
                >
                  {busyId === item.id ? (
                    <ActivityIndicator size="small" color={C.textSecondary} />
                  ) : (
                    <Text style={styles.actionText}>Retry</Text>
                  )}
                </Pressable>
                <Pressable
                  style={styles.actionBtn}
                  onPress={() => onDelete(item)}
                  disabled={busyId === item.id}
                >
                  <Text style={[styles.actionText, styles.actionDeleteText]}>Delete</Text>
                </Pressable>
              </View>
            </TranscriptCard>
          )}
        />
      )}
    </View>
  );
}

function formatDate(iso: string) {
  const d = new Date(iso);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const time = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  if (sameDay) return `Today ${time}`;
  return `${d.toLocaleDateString([], { month: 'short', day: 'numeric' })} ${time}`;
}

const styles = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: C.bg, paddingTop: 60 },
  header: {
    paddingHorizontal: 16,
    paddingBottom: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  back: { color: C.accent, fontFamily: 'Inter-Regular', fontSize: 16, width: 60 },
  title: { color: C.textPrimary, fontFamily: 'Inter-Light', fontSize: 20 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12 },
  emptyText: { color: C.textTertiary, fontFamily: 'Inter-Regular', fontSize: 16 },
  emptyLink: { color: C.accent, fontFamily: 'Inter-Regular', fontSize: 14 },
  row: {
    padding: 16,
    gap: 8,
  },
  timestamp: {
    color: C.textTertiary,
    fontFamily: 'JetBrainsMono-Regular',
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  preview: { color: C.textPrimary, fontFamily: 'Inter-Regular', fontSize: 15, lineHeight: 22 },
  actions: { flexDirection: 'row', gap: 8, marginTop: 4 },
  actionBtn: {
    flex: 1,
    paddingVertical: 9,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: C.hairline,
    alignItems: 'center',
  },
  actionDisabled: { opacity: 0.4 },
  actionText: { color: C.textSecondary, fontFamily: 'Inter-Medium', fontSize: 13 },
  actionDeleteText: { color: C.accent },
});
