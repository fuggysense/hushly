import { StyleSheet, Text, View } from 'react-native';

import { C } from '@/lib/tokens';

type StatusTone = 'idle' | 'live' | 'work' | 'ok' | 'err';

type StatusEyebrowProps = {
  label: string;
  tone?: StatusTone;
};

const toneColor: Record<StatusTone, string> = {
  idle: C.textTertiary,
  live: C.accent,
  work: C.accent,
  ok: C.success,
  err: C.accent,
};

export function StatusEyebrow({ label, tone = 'idle' }: StatusEyebrowProps) {
  const color = toneColor[tone];

  return (
    <View style={styles.wrap}>
      <View style={[styles.dot, { backgroundColor: color }]} />
      <Text style={[styles.text, { color }]}>{label.toUpperCase()}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  dot: {
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  text: {
    fontFamily: 'JetBrainsMono-Regular',
    fontSize: 11,
    letterSpacing: 1.65,
    textTransform: 'uppercase',
    fontVariant: ['tabular-nums'],
  },
});
