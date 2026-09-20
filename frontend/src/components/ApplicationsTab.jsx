import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ExternalLink, Plus, Trash2 } from 'lucide-react';
import { useState } from 'react';

import { api } from '../lib/api.js';

const EMPTY_FORM = { application_name: '', port_number: '', link_url: '', incharge: '', department: '' };

/** Applications filed under a Server (requirement #5) — backed by
 * dbo.applications / v_server_applications. server_type is never entered
 * here: it's derived from the server's hosting_type/os_version by the view,
 * so it can't drift from what the Server record actually says.
 */
export default function ApplicationsTab({ server }) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState(EMPTY_FORM);
  const [adding, setAdding] = useState(false);

  const { data: apps = [], isLoading } = useQuery({
    queryKey: ['applications', server.server_id],
    queryFn: async () => {
      const all = await api.get('/records/applications');
      return all.filter((a) => a.server_id === server.server_id);
    },
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['applications', server.server_id] });

  const addApp = useMutation({
    mutationFn: (values) => api.post('/records/applications', { ...values, server_id: server.server_id }),
    onSuccess: () => {
      setForm(EMPTY_FORM);
      setAdding(false);
      invalidate();
    },
  });

  const deleteApp = useMutation({
    mutationFn: (id) => api.delete(`/records/applications/${id}`),
    onSuccess: invalidate,
  });

  if (isLoading) return <p className="text-ink-muted">กำลังโหลด...</p>;

  return (
    <div>
      <div className="mb-3 flex items-center justify-between">
        <span className="text-sm text-ink-muted">
          Server Type: <span className="font-medium text-ink">{server.hosting_type} / {server.os_version}</span>
        </span>
        <button
          onClick={() => setAdding(true)}
          className="flex items-center gap-1 rounded border border-border px-3 py-1.5 text-sm text-primary hover:bg-primary/5"
        >
          <Plus size={16} strokeWidth={2} />
          เพิ่ม Application
        </button>
      </div>

      {adding && (
        <div className="mb-3 grid grid-cols-2 gap-2 rounded border border-border bg-canvas p-3">
          <input
            className="rounded border border-border px-2 py-1.5 text-sm"
            placeholder="Application Name"
            value={form.application_name}
            onChange={(e) => setForm({ ...form, application_name: e.target.value })}
          />
          <input
            className="rounded border border-border px-2 py-1.5 text-sm"
            placeholder="Port Number"
            value={form.port_number}
            onChange={(e) => setForm({ ...form, port_number: e.target.value })}
          />
          <input
            className="rounded border border-border px-2 py-1.5 text-sm"
            placeholder="Link (https://...)"
            value={form.link_url}
            onChange={(e) => setForm({ ...form, link_url: e.target.value })}
          />
          <input
            className="rounded border border-border px-2 py-1.5 text-sm"
            placeholder="Incharge"
            value={form.incharge}
            onChange={(e) => setForm({ ...form, incharge: e.target.value })}
          />
          <input
            className="col-span-2 rounded border border-border px-2 py-1.5 text-sm"
            placeholder="Department / Section"
            value={form.department}
            onChange={(e) => setForm({ ...form, department: e.target.value })}
          />
          <div className="col-span-2 flex justify-end gap-2">
            <button onClick={() => setAdding(false)} className="rounded border border-border px-3 py-1.5 text-sm">
              ยกเลิก
            </button>
            <button
              onClick={() => addApp.mutate(form)}
              disabled={!form.application_name || addApp.isPending}
              className="rounded bg-primary px-3 py-1.5 text-sm text-white hover:bg-primary-hover disabled:opacity-60"
            >
              บันทึก
            </button>
          </div>
        </div>
      )}

      <table className="w-full text-sm">
        <thead className="text-left text-ink-muted">
          <tr>
            <th className="px-2 py-1.5">Application</th>
            <th className="px-2 py-1.5">Port</th>
            <th className="px-2 py-1.5">Link</th>
            <th className="px-2 py-1.5">Incharge</th>
            <th className="px-2 py-1.5">Department</th>
            <th className="px-2 py-1.5" />
          </tr>
        </thead>
        <tbody>
          {apps.map((app) => (
            <tr key={app.application_id} className="border-t border-border">
              <td className="px-2 py-1.5">{app.application_name}</td>
              <td className="px-2 py-1.5">{app.port_number}</td>
              <td className="px-2 py-1.5">
                {app.link_url && (
                  <a href={app.link_url} target="_blank" rel="noopener noreferrer" className="text-primary hover:underline">
                    <ExternalLink size={14} strokeWidth={1.75} className="inline" />
                  </a>
                )}
              </td>
              <td className="px-2 py-1.5">{app.incharge}</td>
              <td className="px-2 py-1.5">{app.department}</td>
              <td className="px-2 py-1.5 text-right">
                <button onClick={() => deleteApp.mutate(app.application_id)} className="text-ink-muted hover:text-danger">
                  <Trash2 size={14} strokeWidth={1.75} />
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
