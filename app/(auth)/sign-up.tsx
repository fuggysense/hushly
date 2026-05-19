import { useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Link } from 'expo-router';
import { supabase } from '@/lib/supabase';
import { C } from '@/lib/tokens';

export default function SignUp() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit() {
    if (!email || password.length < 8) {
      Alert.alert('Missing', 'Email + password (8+ chars) required.');
      return;
    }
    setBusy(true);
    const { error, data } = await supabase.auth.signUp({ email, password });
    setBusy(false);
    if (error) {
      Alert.alert('Sign-up failed', error.message);
    } else if (!data.session) {
      Alert.alert('Check email', 'Confirm your email to finish signing up.');
    }
  }

  return (
    <View style={styles.wrap}>
      <Text style={styles.title}>Create your hushly account</Text>
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
        placeholder="password (8+ chars)"
        secureTextEntry
        value={password}
        onChangeText={setPassword}
        placeholderTextColor={C.textMuted}
      />
      <Pressable style={styles.btn} onPress={submit} disabled={busy}>
        {busy ? <ActivityIndicator color={C.textPrimary} /> : <Text style={styles.btnText}>Sign up</Text>}
      </Pressable>
      <Link href="/(auth)/sign-in" style={styles.link}>
        Already have an account? Sign in
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
