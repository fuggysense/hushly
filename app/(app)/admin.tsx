import { useCallback, useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Link } from 'expo-router';
import * as Clipboard from 'expo-clipboard';
import { TranscriptCard } from '@/components/TranscriptCard';
import { getStoredSession } from '@/lib/clientAuth';
import { C } from '@/lib/tokens';

type APIKeyRow = {
  id: string;
  label: string;
  tag: string | null;
  key_prefix: string;
  status: string;
  created_at: string;
  last_used_at: string | null;
};

type UsageRow = {
  api_key_id: string | null;
  requests: number;
  transcriptions: number;
  cleanups: number;
  errors: number;
  audio_bytes: number;
  key?: { label: string; tag: string | null; key_prefix: string; status: string } | null;
};

type AdminAccess = {
  email: string;
  isOwner: boolean;
  canManageApiKeys: boolean;
};

export default function Admin() {
  const [access, setAccess] = useState<AdminAccess | null>(null);
  const [label, setLabel] = useState('');
  const [tag, setTag] = useState('');
  const [status, setStatus] = useState('');
  const [createdKey, setCreatedKey] = useState('');
  const [keys, setKeys] = useState<APIKeyRow[]>([]);
  const [usage, setUsage] = useState<UsageRow[]>([]);
  const [userEmail, setUserEmail] = useState('');
  const [userPassword, setUserPassword] = useState('');
  const [userCanManageKeys, setUserCanManageKeys] = useState(true);

  const callAdmin = useCallback(async (body: Record<string, unknown>) => {
    const session = await getStoredSession();
    if (!session) throw new Error('sign-in required');

    setStatus('Loading...');
    const res = await fetch('/admin-keys', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify(body),
    });
    const json = await res.json();
    if (!res.ok) throw new Error(json.error ?? `admin ${res.status}`);
    setStatus('Ready');
    return json;
  }, []);

  const listKeys = useCallback(async () => {
    try {
      const json = await callAdmin({ action: 'list' });
      setAccess(json.access ?? null);
      setKeys(json.keys ?? []);
    } catch (e) {
      setStatus(e instanceof Error ? e.message : String(e));
    }
  }, [callAdmin]);

  const loadUsage = useCallback(async () => {
    try {
      const json = await callAdmin({ action: 'usage', days: 30 });
      setUsage(json.summary ?? []);
    } catch (e) {
      setStatus(e instanceof Error ? e.message : String(e));
    }
  }, [callAdmin]);

  const refreshAdmin = useCallback(async () => {
    await listKeys();
    await loadUsage();
  }, [listKeys, loadUsage]);

  useEffect(() => {
    void refreshAdmin();
  }, [refreshAdmin]);

  const createKey = async () => {
    try {
      setCreatedKey('');
      const json = await callAdmin({ action: 'create', label, tag });
      setCreatedKey(json.key ?? '');
      setLabel('');
      await refreshAdmin();
    } catch (e) {
      setStatus(e instanceof Error ? e.message : String(e));
    }
  };

  const resetUserPassword = async () => {
    try {
      await callAdmin({
        action: 'upsertUser',
        email: userEmail,
        password: userPassword,
        can_manage_api_keys: userCanManageKeys,
      });
      setUserPassword('');
      setStatus('Sign-in saved for this email.');
    } catch (e) {
      setStatus(e instanceof Error ? e.message : String(e));
    }
  };

  const copyCreatedKey = async () => {
    if (!createdKey) return;
    await Clipboard.setStringAsync(createdKey);
    setStatus('API key copied');
  };

  const revokeKey = async (id: string) => {
    try {
      await callAdmin({ action: 'revoke', id });
      await refreshAdmin();
    } catch (e) {
      setStatus(e instanceof Error ? e.message : String(e));
    }
  };

  const deleteKey = async (id: string) => {
    try {
      await callAdmin({ action: 'delete', id });
      await refreshAdmin();
    } catch (e) {
      setStatus(e instanceof Error ? e.message : String(e));
    }
  };

  return (
    <View style={styles.wrap}>
      <View style={styles.header}>
        <Link href="/(app)" style={styles.back}>
          back
        </Link>
        <Text style={styles.title}>Admin</Text>
        <View style={{ width: 72 }} />
      </View>

      <ScrollView contentContainerStyle={styles.content}>
        <TranscriptCard style={styles.card}>
          <Text style={styles.eyebrow}>Access</Text>
          <Text style={styles.line}>{access?.email ?? 'Signed-in account'}</Text>
          <Text style={styles.line}>
            {access?.isOwner ? 'Owner' : access?.canManageApiKeys ? 'API key manager' : 'No API key access'}
          </Text>
          <View style={styles.actions}>
            <Pressable style={styles.secondary} onPress={() => refreshAdmin()}>
              <Text style={styles.secondaryText}>Refresh</Text>
            </Pressable>
          </View>
          <Text style={styles.status}>{status || 'Ready'}</Text>
        </TranscriptCard>

        {access?.isOwner ? (
          <TranscriptCard style={styles.card}>
            <Text style={styles.eyebrow}>Create or reset sign-in</Text>
            <TextInput
              value={userEmail}
              onChangeText={setUserEmail}
              style={styles.input}
              placeholder="Email"
              placeholderTextColor={C.textMuted}
              autoCapitalize="none"
              keyboardType="email-address"
            />
            <TextInput
              value={userPassword}
              onChangeText={setUserPassword}
              secureTextEntry
              style={styles.input}
              placeholder="New password (8+ chars)"
              placeholderTextColor={C.textMuted}
            />
            <Pressable
              style={[styles.secondary, userCanManageKeys && styles.selectedToggle]}
              onPress={() => setUserCanManageKeys((value) => !value)}
            >
              <Text style={styles.secondaryText}>
                {userCanManageKeys ? 'API key access on' : 'API key access off'}
              </Text>
            </Pressable>
            <Pressable style={styles.primary} onPress={resetUserPassword}>
              <Text style={styles.primaryText}>Save sign-in</Text>
            </Pressable>
          </TranscriptCard>
        ) : null}

        {access?.canManageApiKeys ? (
          <TranscriptCard style={styles.card}>
            <Text style={styles.eyebrow}>Create API key</Text>
            <TextInput
              value={label}
              onChangeText={setLabel}
              style={styles.input}
              placeholder="Label"
              placeholderTextColor={C.textMuted}
            />
            <TextInput
              value={tag}
              onChangeText={setTag}
              style={styles.input}
              placeholder="Tag"
              placeholderTextColor={C.textMuted}
            />
            <Pressable style={styles.primary} onPress={createKey}>
              <Text style={styles.primaryText}>Create</Text>
            </Pressable>
          </TranscriptCard>
        ) : (
          <TranscriptCard style={styles.card}>
            <Text style={styles.eyebrow}>API key access</Text>
            <Text style={styles.line}>This signed-in account cannot create or manage API keys.</Text>
          </TranscriptCard>
        )}

        {createdKey ? (
          <TranscriptCard style={styles.createdCard}>
            <Text style={styles.eyebrow}>New API key</Text>
            <Text style={styles.line}>Copy it now. The full key is shown only once.</Text>
            <Text style={styles.keyText} selectable>
              {createdKey}
            </Text>
            <Pressable style={styles.primary} onPress={copyCreatedKey}>
              <Text style={styles.primaryText}>Copy API key</Text>
            </Pressable>
          </TranscriptCard>
        ) : null}

        {access?.canManageApiKeys ? (
          <View style={styles.actions}>
            <Pressable style={styles.secondary} onPress={() => listKeys()}>
              <Text style={styles.secondaryText}>List keys</Text>
            </Pressable>
            <Pressable style={styles.secondary} onPress={() => loadUsage()}>
              <Text style={styles.secondaryText}>Usage</Text>
            </Pressable>
          </View>
        ) : null}

        {keys.map((key) => (
          <TranscriptCard key={key.id} style={styles.card}>
            <Text style={styles.keyTitle}>{key.label}</Text>
            <Text style={styles.line}>
              {key.key_prefix} · {key.status}{key.tag ? ` · ${key.tag}` : ''}
            </Text>
            <Text style={styles.line}>
              Created {formatDate(key.created_at)}
              {key.last_used_at ? ` · Last used ${formatDate(key.last_used_at)}` : ''}
            </Text>
            {key.status === 'active' ? (
              <Pressable style={styles.secondary} onPress={() => revokeKey(key.id)}>
                <Text style={styles.secondaryText}>Revoke</Text>
              </Pressable>
            ) : key.status === 'revoked' ? (
              <Pressable style={styles.secondaryDanger} onPress={() => deleteKey(key.id)}>
                <Text style={styles.secondaryDangerText}>Delete revoked key</Text>
              </Pressable>
            ) : null}
          </TranscriptCard>
        ))}

        {usage.length ? (
          usage.map((row, index) => (
            <TranscriptCard key={`${row.api_key_id ?? row.key?.key_prefix ?? 'user'}-${index}`} style={styles.card}>
              <Text style={styles.keyTitle}>{row.key?.label ?? row.api_key_id ?? 'Signed-in user'}</Text>
              <Text style={styles.line}>
                {row.key?.key_prefix ? `${row.key.key_prefix} · ` : ''}{row.key?.status ?? 'usage'}
                {row.key?.tag ? ` · ${row.key.tag}` : ''}
              </Text>
              <Text style={styles.line}>
                {row.requests} requests · {row.transcriptions} transcriptions · {row.cleanups} cleanups · {row.errors} errors
              </Text>
              <Text style={styles.line}>{byteString(row.audio_bytes)} audio uploaded</Text>
            </TranscriptCard>
          ))
        ) : (
          <Text style={styles.line}>No usage logged in the last 30 days.</Text>
        )}
      </ScrollView>
    </View>
  );
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
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
  content: { padding: 16, gap: 12 },
  card: { padding: 16, gap: 10 },
  createdCard: { padding: 16, gap: 10, borderColor: C.accent },
  eyebrow: {
    color: C.textTertiary,
    fontFamily: 'JetBrainsMono-Regular',
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 0,
  },
  input: {
    color: C.textPrimary,
    backgroundColor: C.elevated,
    borderWidth: 1,
    borderColor: C.hairline,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontFamily: 'Inter-Regular',
    fontSize: 14,
  },
  status: { color: C.textTertiary, fontFamily: 'Inter-Regular', fontSize: 13 },
  actions: { flexDirection: 'row', gap: 10 },
  primary: { alignItems: 'center', backgroundColor: C.accent, borderRadius: 8, paddingVertical: 10 },
  primaryText: { color: C.bg, fontFamily: 'Inter-Medium', fontSize: 14 },
  secondary: {
    alignItems: 'center',
    borderColor: C.hairline,
    borderRadius: 8,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 9,
  },
  selectedToggle: { borderColor: C.accent },
  secondaryText: { color: C.textSecondary, fontFamily: 'Inter-Medium', fontSize: 13 },
  secondaryDanger: {
    alignItems: 'center',
    borderColor: C.accent,
    borderRadius: 8,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 9,
  },
  secondaryDangerText: { color: C.accent, fontFamily: 'Inter-Medium', fontSize: 13 },
  keyText: { color: C.accent, fontFamily: 'JetBrainsMono-Regular', fontSize: 12, lineHeight: 18 },
  keyTitle: { color: C.textPrimary, fontFamily: 'Inter-Medium', fontSize: 16 },
  line: { color: C.textSecondary, fontFamily: 'Inter-Regular', fontSize: 13, lineHeight: 19 },
});
