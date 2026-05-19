import { useEffect } from 'react';
import { View } from 'react-native';
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withDelay,
  withRepeat,
  withTiming,
} from 'react-native-reanimated';

function Bar({ delay, active }: { delay: number; active: boolean }) {
  const s = useSharedValue(0.2);
  useEffect(() => {
    s.value = active
      ? withDelay(
          delay,
          withRepeat(withTiming(1, { duration: 350, easing: Easing.inOut(Easing.ease) }), -1, true)
        )
      : withTiming(0.2, { duration: 200 });
  }, [active, delay, s]);
  const style = useAnimatedStyle(() => ({ transform: [{ scaleY: s.value }] }));
  return (
    <Animated.View
      style={[{ width: 3, height: 18, marginHorizontal: 2, backgroundColor: '#fff', borderRadius: 2 }, style]}
    />
  );
}

export function Waveform({ active }: { active: boolean }) {
  const delays = [0, 80, 160, 60, 200, 40, 140, 100, 180];
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', height: 24 }}>
      {delays.map((d, i) => (
        <Bar key={i} delay={d} active={active} />
      ))}
    </View>
  );
}
