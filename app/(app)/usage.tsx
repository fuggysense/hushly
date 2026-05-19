import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Link } from 'expo-router';
import { TranscriptCard } from '@/components/TranscriptCard';
import { getUsageSummary } from '@/lib/api';
import { C } from '@/lib/tokens';

type UsageSummary = NonNullable<Awaited<ReturnType<typeof getUsageSummary>>>;

export default function Usage() {
  const [usage, setUsage] = useState<UsageSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      setUsage(await getUsageSummary());
    } catch (e) {
      setUsage(null);
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <View style={styles.wrap}>
      <View style={styles.header}>
        <Link href="/(app)" style={styles.back}>
          back
        </Link>
        <Text style={styles.title}>Usage</Text>
        <Pressable onPress={load} style={styles.refresh}>
          <Text style={styles.refreshText}>Refresh</Text>
        </Pressable>
      </View>

      <ScrollView contentContainerStyle={styles.content}>
        {loading ? (
          <ActivityIndicator color={C.textTertiary} />
        ) : usage ? (
          <>
            <TranscriptCard style={styles.card}>
              <Text style={styles.eyebrow}>Today</Text>
              <Text style={styles.big}>{usage.today.requests} requests</Text>
              <Text style={styles.line}>
                {usage.today.transcriptions} transcriptions · {usage.today.cleanups} cleanups · {usage.today.errors} errors
              </Text>
              <Text style={styles.line}>{byteString(usage.today.audioBytes)} audio uploaded</Text>
            </TranscriptCard>

            <TranscriptCard style={styles.card}>
              <Text style={styles.eyebrow}>Last 30 days</Text>
              <Text style={styles.big}>{usage.last30d.requests} requests</Text>
              <Text style={styles.line}>
                {usage.last30d.transcriptions} transcriptions · {usage.last30d.cleanups} cleanups · {usage.last30d.errors} errors
              </Text>
              <Text style={styles.line}>{byteString(usage.last30d.audioBytes)} audio uploaded</Text>
            </TranscriptCard>
          </>
        ) : error ? (
          <Text style={styles.line}>{error}</Text>
        ) : (
          <Text style={styles.line}>Usage is unavailable for this session.</Text>
        )}
      </ScrollView>
    </View>
  );
}

function byteString(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(1)} KB`;
  return `${(kb / 1024).toFixed(1)} MB`;
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
  back: { color: C.accent, fontFamily: 'Inter-Regular', fontSize: 16, width: 72 },
  title: { color: C.textPrimary, fontFamily: 'Inter-Light', fontSize: 20 },
  refresh: { width: 72, alignItems: 'flex-end' },
  refreshText: { color: C.textSecondary, fontFamily: 'Inter-Medium', fontSize: 13 },
  content: { padding: 16, gap: 12 },
  card: { padding: 16, gap: 8 },
  eyebrow: {
    color: C.textTertiary,
    fontFamily: 'JetBrainsMono-Regular',
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 0,
  },
  big: { color: C.textPrimary, fontFamily: 'Inter-Light', fontSize: 28 },
  line: { color: C.textSecondary, fontFamily: 'Inter-Regular', fontSize: 14, lineHeight: 20 },
});
