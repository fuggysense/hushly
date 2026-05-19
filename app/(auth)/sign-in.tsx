import { useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Link } from 'expo-router';
import { supabase } from '@/lib/supabase';
import { C } from '@/lib/tokens';

export default function SignIn() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit() {
    if (!email || !password) {
      Alert.alert('Missing', 'Email and password required.');
      return;
    }
    setBusy(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) Alert.alert('Sign-in failed', error.message);
  }

  return (
    <View style={styles.wrap}>
      <Text style={styles.title}>Sign in to hushly</Text>
      <TextInput
        style={styles.input}
        placeholder="you@example.com"
        autoCapitalize="none"
        autoCorrect={false}
        keyboardType="email-address"
        value={email}
        onChangeText={setEmail}
        placeholderTextColor={C.textMuted}
      />
      <TextInput
        style={styles.input}
        placeholder="password"
        secureTextEntry
        value={password}
        onChangeText={setPassword}
        placeholderTextColor={C.textMuted}
      />
      <Pressable style={styles.btn} onPress={submit} disabled={busy}>
        {busy ? <ActivityIndicator color={C.textPrimary} /> : <Text style={styles.btnText}>Sign in</Text>}
      </Pressable>
      <Link href="/(auth)/sign-up" style={styles.link}>
        No account? Sign up
      </Link>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { flex: 1, justifyContent: 'center', padding: 24, gap: 12, backgroundColor: C.bg },
  title: { color: C.textPrimary, fontFamily: 'Inter-Light', fontSize: 28, marginBottom: 12 },
  input: {
    backgroundColor: C.elevated,
    color: C.textPrimary,
    fontFamily: 'Inter-Regular',
    padding: 14,
    borderRadius: 10,
    fontSize: 16,
  },
  btn: {
    backgroundColor: C.accent,
    padding: 14,
    borderRadius: 10,
    alignItems: 'center',
    marginTop: 4,
  },
  btnText: { color: C.textPrimary, fontFamily: 'Inter-Medium', fontSize: 16 },
  link: { color: C.accent, fontFamily: 'Inter-Regular', textAlign: 'center', marginTop: 16 },
});
