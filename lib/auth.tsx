import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import {
  getStoredSession,
  onSessionChange,
  type HushlySession,
} from './clientAuth';

type AuthState = {
  session: HushlySession | null;
  loading: boolean;
};

const AuthContext = createContext<AuthState>({ session: null, loading: true });

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<HushlySession | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;
    getStoredSession().then((stored) => {
      if (!mounted) return;
      setSession(stored);
      setLoading(false);
    });
    const unsubscribe = onSessionChange((next) => setSession(next));
    return () => {
      mounted = false;
      unsubscribe();
    };
  }, []);

  return <AuthContext.Provider value={{ session, loading }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  return useContext(AuthContext);
}
