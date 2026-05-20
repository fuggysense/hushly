import { Platform } from 'react-native';

export const DEFAULT_API_BASE = 'https://hushly.genflos.com';

export function getApiBase(): string {
  if (Platform.OS === 'web' && typeof window !== 'undefined') {
    return window.location.origin;
  }
  const explicit = process.env.EXPO_PUBLIC_API_BASE;
  if (explicit) return explicit.replace(/\/$/, '');
  return DEFAULT_API_BASE;
}
