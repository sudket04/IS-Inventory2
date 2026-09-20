import { useQuery } from '@tanstack/react-query';
import { Lock, Pencil, Plus } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router-dom';

import SiteBadge from '../components/SiteBadge.jsx';
import { useAuth, ROLE_ADMIN } from '../lib/AuthContext.jsx';
import { api } from '../lib/api.js';

/** List + filter as a plain table column (per the UX decision — no separate
 * site switcher). Rows outside the current user's site scope render their
 * Edit action as a disabled lock icon instead of hiding the row: Staff can
 * always SEE every site, editing is what's restricted.
 */
export default function Servers() {
  const { user } = useAuth();
  const [siteFilter, setSiteFilter] = useState('');

  const { data: servers = [], isLoading } = useQuery({
    queryKey: ['v_asset_360'],
    queryFn: () => api.get('/records/servers'),
  });

  const canEditSite = (locationId) => user?.role_id === ROLE_ADMIN || user?.site_ids?.includes(locationId);

  const filtered = siteFilter ? servers.filter((s) => s.site_name === siteFilter) : servers;
  const siteNames = [...new Set(servers.map((s) => s.site_name).filter(Boolean))];

  if (isLoading) return <p className="text-ink-muted">กำลังโหลด...</p>;

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <h1 className="text-lg font-semibold text-ink">Server</h1>
        <button className="flex items-center gap-1 rounded bg-primary px-3 py-2 text-sm text-white hover:bg-primary-hover">
          <Plus size={16} strokeWidth={2} />
          เพิ่มใหม่
        </button>
      </div>

      <div className="mb-3">
        <select
          className="rounded border border-border px-3 py-1.5 text-sm"
          value={siteFilter}
          onChange={(e) => setSiteFilter(e.target.value)}
        >
          <option value="">ทุก Site</option>
          {siteNames.map((name) => (
            <option key={name} value={name}>
              {name}
            </option>
          ))}
        </select>
      </div>

      <table className="w-full overflow-hidden rounded border border-border bg-surface text-sm">
        <thead className="bg-canvas text-left text-ink-muted">
          <tr>
            <th className="px-4 py-2">Server Name</th>
            <th className="px-4 py-2">Hosting</th>
            <th className="px-4 py-2">Site</th>
            <th className="px-4 py-2">Status</th>
            <th className="px-4 py-2 text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          {filtered.map((server) => {
            const editable = canEditSite(server.location_id);
            return (
              <tr key={server.server_id} className="border-t border-border">
                <td className="px-4 py-2">
                  <Link to={`/servers/${server.server_id}`} className="text-primary hover:underline">
                    {server.server_name}
                  </Link>
                </td>
                <td className="px-4 py-2">{server.hosting_type}</td>
                <td className="px-4 py-2">
                  <SiteBadge siteName={server.site_name} />
                </td>
                <td className="px-4 py-2">{server.status}</td>
                <td className="px-4 py-2 text-right">
                  {editable ? (
                    <button className="text-ink-muted hover:text-primary">
                      <Pencil size={16} strokeWidth={1.75} />
                    </button>
                  ) : (
                    <span title="อยู่นอกสิทธิ์แก้ไขของคุณ" className="cursor-not-allowed text-ink-muted/50">
                      <Lock size={16} strokeWidth={1.75} />
                    </span>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
