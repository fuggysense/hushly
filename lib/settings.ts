// Per-user button + shortcut preferences.
// Stored in AsyncStorage (native) / localStorage (web) so it works offline
// and survives reloads. Future: sync to profiles table.

import AsyncStorage from '@react-native-async-storage/async-storage';
import { useEffect, useState } from 'react';

export type ButtonSettings = {
  label: string;
  recordingLabel: string;
  shortcutKey: string;
};

const DEFAULTS: ButtonSettings = {
  label: 'Tap to record',
  recordingLabel: 'Tap to stop',
  shortcutKey: ' ', // Spacebar on web
};

const KEY = 'hushly:button-settings';

export async function loadSettings(): Promise<ButtonSettings> {
  try {
    const raw = await AsyncStorage.getItem(KEY);
    if (!raw) return DEFAULTS;
    const parsed = JSON.parse(raw) as Partial<ButtonSettings>;
    return { ...DEFAULTS, ...parsed };
  } catch {
    return DEFAULTS;
  }
}

export async function saveSettings(s: ButtonSettings): Promise<void> {
  await AsyncStorage.setItem(KEY, JSON.stringify(s));
}

export function useButtonSettings(): [ButtonSettings, (next: ButtonSettings) => Promise<void>] {
  const [s, setS] = useState<ButtonSettings>(DEFAULTS);

  useEffect(() => {
    loadSettings().then(setS);
  }, []);

  const update = async (next: ButtonSettings) => {
    setS(next);
    await saveSettings(next);
  };

  return [s, update];
}
