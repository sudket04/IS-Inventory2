import { LayoutDashboard, LogOut, Network, Server, ShieldCheck, User as UserIcon } from 'lucide-react';
import { NavLink, Outlet } from 'react-router-dom';

import { useAuth } from '../lib/AuthContext.jsx';

const NAV_ITEMS = [
  { to: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/servers', label: 'Server', icon: Server },
  { to: '/vlans', label: 'VLAN', icon: Network },
];

/** Standard outline icons (Lucide) only, per the Design System rules —
 * emoji are never used for menu/status iconography anywhere in this app.
 */
export default function Layout() {
  const { user, logout } = useAuth();

  return (
    <div className="flex min-h-screen">
      <aside className="w-56 border-r border-border bg-surface">
        <div className="border-b border-border p-4 text-sm font-semibold text-ink">IS Inventory</div>
        <nav className="p-2">
          {NAV_ITEMS.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                `mb-1 flex items-center gap-2 rounded px-3 py-2 text-sm ${
                  isActive ? 'bg-primary/10 text-primary' : 'text-ink-muted hover:bg-canvas'
                }`
              }
            >
              <Icon size={18} strokeWidth={1.75} />
              {label}
            </NavLink>
          ))}
          {user?.role_id === 'ROL-004' && (
            <NavLink
              to="/audit"
              className={({ isActive }) =>
                `mb-1 flex items-center gap-2 rounded px-3 py-2 text-sm ${
                  isActive ? 'bg-primary/10 text-primary' : 'text-ink-muted hover:bg-canvas'
                }`
              }
            >
              <ShieldCheck size={18} strokeWidth={1.75} />
              Audit Log
            </NavLink>
          )}
        </nav>
      </aside>

      <div className="flex-1">
        <header className="flex items-center justify-between border-b border-border bg-surface px-6 py-3">
          <div />
          <div className="flex items-center gap-3 text-sm text-ink-muted">
            <UserIcon size={16} strokeWidth={1.75} />
            <span>{user?.sub}</span>
            <span className="rounded bg-canvas px-2 py-0.5 text-xs">{user?.role_id}</span>
            <button onClick={logout} className="flex items-center gap-1 text-ink-muted hover:text-danger">
              <LogOut size={16} strokeWidth={1.75} />
              ออกจากระบบ
            </button>
          </div>
        </header>
        <main className="p-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
