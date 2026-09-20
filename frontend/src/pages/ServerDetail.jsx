import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { useParams } from 'react-router-dom';

import ApplicationsTab from '../components/ApplicationsTab.jsx';
import SiteBadge from '../components/SiteBadge.jsx';
import { api } from '../lib/api.js';

const TABS = ['General', 'Applications'];

export default function ServerDetail() {
  const { serverId } = useParams();
  const [tab, setTab] = useState('General');

  const { data: server, isLoading } = useQuery({
    queryKey: ['server', serverId],
    queryFn: () => api.get(`/records/servers/${serverId}`),
  });

  if (isLoading || !server) return <p className="text-ink-muted">กำลังโหลด...</p>;

  return (
    <div className="max-w-3xl">
      <div className="mb-4 flex items-center gap-3">
        <h1 className="text-lg font-semibold text-ink">{server.server_name}</h1>
        <SiteBadge siteName={server.site_name} />
      </div>

      <div className="mb-4 flex gap-1 border-b border-border">
        {TABS.map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2 text-sm ${
              tab === t ? 'border-b-2 border-primary font-medium text-primary' : 'text-ink-muted'
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'General' && (
        <dl className="grid grid-cols-2 gap-3 rounded border border-border bg-surface p-4 text-sm">
          <div>
            <dt className="text-ink-muted">System Name</dt>
            <dd>{server.system_name}</dd>
          </div>
          <div>
            <dt className="text-ink-muted">Hosting Type</dt>
            <dd>{server.hosting_type}</dd>
          </div>
          <div>
            <dt className="text-ink-muted">OS</dt>
            <dd>{server.os_version}</dd>
          </div>
          <div>
            <dt className="text-ink-muted">Status</dt>
            <dd>{server.status}</dd>
          </div>
        </dl>
      )}

      {tab === 'Applications' && (
        <div className="rounded border border-border bg-surface p-4">
          <ApplicationsTab server={server} />
        </div>
      )}
    </div>
  );
}
