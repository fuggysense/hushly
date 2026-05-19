import type { ReactNode } from 'react';
import { StyleSheet, View } from 'react-native';
import type { StyleProp, ViewStyle } from 'react-native';

import { C } from '@/lib/tokens';

type TranscriptCardProps = {
  children: ReactNode;
  style?: StyleProp<ViewStyle>;
};

export function TranscriptCard({ children, style }: TranscriptCardProps) {
  return (
    <View style={[styles.card, style]}>
      <View style={styles.cornerHorizontal} />
      <View style={styles.cornerVertical} />
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    position: 'relative',
    backgroundColor: C.surface,
    borderWidth: 1,
    borderColor: C.hairline,
    borderRadius: 8,
    padding: 24,
  },
  cornerHorizontal: {
    position: 'absolute',
    top: 0,
    left: 0,
    width: 8,
    height: 1,
    backgroundColor: C.accent,
  },
  cornerVertical: {
    position: 'absolute',
    top: 0,
    left: 0,
    width: 1,
    height: 8,
    backgroundColor: C.accent,
  },
});
