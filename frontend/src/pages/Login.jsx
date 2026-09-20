import { useState } from 'react';
import { useNavigate } from 'react-router-dom';

import { useAuth } from '../lib/AuthContext.jsx';

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      await login(username, password);
      navigate('/servers');
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-canvas">
      <form onSubmit={handleSubmit} className="w-80 rounded border border-border bg-surface p-6 shadow-sm">
        <h1 className="mb-4 text-lg font-semibold text-ink">IS Inventory</h1>

        <label className="mb-3 block">
          <span className="mb-1 block text-sm font-medium text-ink">Username</span>
          <input
            className="w-full rounded border border-border px-3 py-2 text-sm focus:border-primary focus:outline-none"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoFocus
            required
          />
        </label>

        <label className="mb-4 block">
          <span className="mb-1 block text-sm font-medium text-ink">Password</span>
          <input
            type="password"
            className="w-full rounded border border-border px-3 py-2 text-sm focus:border-primary focus:outline-none"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>

        {error && <p className="mb-3 text-sm text-danger">{error}</p>}

        <button
          type="submit"
          disabled={busy}
          className="w-full rounded bg-primary py-2 text-sm font-medium text-white hover:bg-primary-hover disabled:opacity-60"
        >
          {busy ? 'กำลังเข้าสู่ระบบ...' : 'เข้าสู่ระบบ'}
        </button>
      </form>
    </div>
  );
}
