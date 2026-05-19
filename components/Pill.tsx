import type { ReactNode } from 'react';
import { StyleSheet, View } from 'react-native';
import type { StyleProp, ViewStyle } from 'react-native';

import { C } from '@/lib/tokens';

type PillProps = {
  left?: ReactNode;
  center?: ReactNode;
  right?: ReactNode;
  style?: StyleProp<ViewStyle>;
};

export function Pill({ left, center, right, style }: PillProps) {
  return (
    <View style={[styles.pill, style]}>
      <View style={styles.slot}>{left}</View>
      <View style={styles.centerSlot}>{center}</View>
      <View style={styles.slot}>{right}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  pill: {
    width: '100%',
    maxWidth: 280,
    minHeight: 56,
    borderRadius: 999,
    backgroundColor: '#000',
    borderWidth: 1,
    borderColor: C.hairline,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 16,
    gap: 12,
  },
  slot: {
    minWidth: 28,
    minHeight: 28,
    alignItems: 'center',
    justifyContent: 'center',
  },
  centerSlot: {
    minWidth: 72,
    minHeight: 28,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
