import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';

import SiteBadge from '../components/SiteBadge.jsx';
import { api } from '../lib/api.js';

export default function VlanList() {
  const { data: vlans = [], isLoading } = useQuery({
    queryKey: ['vlans'],
    queryFn: () => api.get('/records/vlans'),
  });

  if (isLoading) return <p className="text-ink-muted">กำลังโหลด...</p>;

  return (
    <div>
      <h1 className="mb-4 text-lg font-semibold text-ink">VLAN</h1>
      <table className="w-full overflow-hidden rounded border border-border bg-surface text-sm">
        <thead className="bg-canvas text-left text-ink-muted">
          <tr>
            <th className="px-4 py-2">Tag</th>
            <th className="px-4 py-2">Name</th>
            <th className="px-4 py-2">Device</th>
            <th className="px-4 py-2">Zone</th>
          </tr>
        </thead>
        <tbody>
          {vlans.map((v) => (
            <tr key={v.vlan_id_pk} className="border-t border-border">
              <td className="px-4 py-2">
                <Link to={`/vlans/${v.vlan_id_pk}`} className="text-primary hover:underline">
                  {v.is_untagged ? 'Untagged' : v.vlan_tag}
                </Link>
              </td>
              <td className="px-4 py-2">{v.vlan_name}</td>
              <td className="px-4 py-2">{v.device_name}</td>
              <td className="px-4 py-2">{v.vlan_zone}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
