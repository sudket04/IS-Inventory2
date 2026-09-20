import { createContext, useContext, useEffect, useState } from 'react';

import { api } from './api.js';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(undefined); // undefined = still checking, null = logged out

  useEffect(() => {
    api.get('/auth/me').then(setUser).catch(() => setUser(null));
  }, []);

  async function login(username, password) {
    const result = await api.post('/auth/login', { username, password });
    setUser({ sub: result.user_id, role_id: result.role_id, site_ids: [] });
    return result;
  }

  async function logout() {
    await api.post('/auth/logout', {});
    setUser(null);
  }

  return <AuthContext.Provider value={{ user, login, logout }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  return useContext(AuthContext);
}

// "Admin" means role_id ROL-001, per the seed in db/10_seed.sql. Keeping the
// id here means nothing else hardcodes it.
export const ROLE_ADMIN = 'ROL-001';
