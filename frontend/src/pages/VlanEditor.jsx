import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';

import SiteSelect from '../components/SiteSelect.jsx';
import SubnetRow from '../components/SubnetRow.jsx';
import { useAuth, ROLE_ADMIN } from '../lib/AuthContext.jsx';
import { api } from '../lib/api.js';

/** Editor for one VLAN — the page that had to change shape for requirements
 * #2-#4: Untagged vs numbered tag, N subnets per VLAN (Primary/Secondary =
 * "VLAN Level"), and per-subnet static ranges + DHCP that no longer assumes
 * DHCP is "whatever's left after one static block".
 */
export default function VlanEditor() {
  const { vlanId } = useParams();
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const { data: vlan, isLoading } = useQuery({
    queryKey: ['vlan', vlanId],
    queryFn: () => api.get(`/vlans/${vlanId}/full`),
  });

  const { data: sites = [] } = useQuery({
    queryKey: ['sites'],
    queryFn: async () => (await api.get('/records/locations')).filter((l) => l.level === 'Site'),
  });

  const [form, setForm] = useState(null);
  const [isUntagged, setIsUntagged] = useState(false);

  useEffect(() => {
    if (vlan) {
      setForm(vlan);
      setIsUntagged(vlan.vlan_tag === null);
    }
  }, [vlan]);

  const canEdit = user?.role_id === ROLE_ADMIN || user?.site_ids?.includes(form?.location_id);

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['vlan', vlanId] });

  const saveVlan = useMutation({
    mutationFn: (values) => api.put(`/records/vlans/${vlanId}`, values),
    onSuccess: invalidate,
  });

  const addSubnet = useMutation({
    mutationFn: () =>
      api.post(`/vlans/${vlanId}/subnets`, {
        level: form.subnets.some((s) => s.level === 'Primary') ? 'Secondary' : 'Primary',
        network_address: '',
        prefix_len: 24,
        ip_assignment: 'Static',
      }),
    onSuccess: invalidate,
  });

  const updateSubnet = useMutation({
    mutationFn: ({ subnetId, values }) => api.put(`/vlans/subnets/${subnetId}`, values),
    onSuccess: invalidate,
  });

  const deleteSubnet = useMutation({
    mutationFn: (subnetId) => api.delete(`/vlans/subnets/${subnetId}`),
    onSuccess: invalidate,
  });

  const addRange = useMutation({
    mutationFn: ({ subnetId, values }) => api.post(`/vlans/subnets/${subnetId}/static-ranges`, values),
    onSuccess: invalidate,
    onError: (err) => alert(err.message),
  });

  const deleteRange = useMutation({
    mutationFn: (rangeId) => api.delete(`/vlans/static-ranges/${rangeId}`),
    onSuccess: invalidate,
  });

  if (isLoading || !form) return <p className="text-ink-muted">กำลังโหลด...</p>;

  return (
    <div className="max-w-3xl space-y-4">
      <h1 className="text-lg font-semibold text-ink">VLAN: {form.vlan_name}</h1>

      <div className="rounded border border-border bg-surface p-4">
        <div className="mb-3 grid grid-cols-2 gap-3">
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-ink">VLAN Tag</span>
            <div className="flex items-center gap-2">
              <input
                disabled={!canEdit || isUntagged}
                type="number"
                min={1}
                max={4094}
                className="w-full rounded border border-border px-3 py-2 text-sm disabled:bg-canvas"
                value={form.vlan_tag ?? ''}
                onChange={(e) => setForm({ ...form, vlan_tag: e.target.value })}
              />
              <label className="flex items-center gap-1.5 whitespace-nowrap text-sm text-ink-muted">
                <input
                  disabled={!canEdit}
                  type="checkbox"
                  checked={isUntagged}
                  onChange={(e) => {
                    setIsUntagged(e.target.checked);
                    if (e.target.checked) setForm({ ...form, vlan_tag: null });
                  }}
                />
                Untagged
              </label>
            </div>
          </label>

          <SiteSelect
            value={form.location_id}
            onChange={(v) => setForm({ ...form, location_id: v })}
            siteOptions={sites}
          />
        </div>

        <div className="mb-3 grid grid-cols-3 gap-3">
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-ink">VLAN Name</span>
            <input
              disabled={!canEdit}
              className="w-full rounded border border-border px-3 py-2 text-sm"
              value={form.vlan_name || ''}
              onChange={(e) => setForm({ ...form, vlan_name: e.target.value })}
            />
          </label>
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-ink">Zone</span>
            <input
              disabled={!canEdit}
              className="w-full rounded border border-border px-3 py-2 text-sm"
              value={form.vlan_zone || ''}
              onChange={(e) => setForm({ ...form, vlan_zone: e.target.value })}
            />
          </label>
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-ink">Device</span>
            <input
              disabled={!canEdit}
              className="w-full rounded border border-border px-3 py-2 text-sm"
              value={form.device_name || ''}
              onChange={(e) => setForm({ ...form, device_name: e.target.value })}
            />
          </label>
        </div>

        {canEdit && (
          <button
            onClick={() =>
              saveVlan.mutate({
                vlan_tag: isUntagged ? null : Number(form.vlan_tag) || null,
                vlan_name: form.vlan_name,
                vlan_zone: form.vlan_zone,
                device_name: form.device_name,
                location_id: form.location_id,
                updated_at: form.updated_at,
              })
            }
            disabled={saveVlan.isPending}
            className="rounded bg-primary px-4 py-2 text-sm font-medium text-white hover:bg-primary-hover"
          >
            บันทึก VLAN
          </button>
        )}
        {saveVlan.isError && <p className="mt-2 text-sm text-danger">{saveVlan.error.message}</p>}
      </div>

      <div>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-ink">Subnets ({form.subnets.length})</h2>
          {canEdit && (
            <button
              onClick={() => addSubnet.mutate()}
              className="flex items-center gap-1 rounded border border-border px-3 py-1.5 text-sm text-primary hover:bg-primary/5"
            >
              <Plus size={16} strokeWidth={2} />
              เพิ่ม Subnet
            </button>
          )}
        </div>

        <div className="space-y-3">
          {form.subnets.map((subnet) => (
            <SubnetRow
              key={subnet.subnet_id}
              subnet={subnet}
              canEdit={canEdit}
              onChange={(next) => updateSubnet.mutate({ subnetId: subnet.subnet_id, values: next })}
              onDelete={() => deleteSubnet.mutate(subnet.subnet_id)}
              onAddRange={(range) => addRange.mutate({ subnetId: subnet.subnet_id, values: range })}
              onDeleteRange={(rangeId) => deleteRange.mutate(rangeId)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
