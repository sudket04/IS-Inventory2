import { Plus, Trash2 } from 'lucide-react';
import { useState } from 'react';

/** One dbo.vlan_subnets row: Primary/Secondary level, the subnet itself,
 * IP Assignment (Static / DHCP / Static+DHCP), and — the part the old
 * single-range design couldn't do — as many disjoint static ranges as this
 * subnet actually needs, plus an explicit DHCP pool that can sit anywhere
 * inside the subnet (including between two static ranges, like the real
 * WIFI-Data-Center /21).
 */
export default function SubnetRow({ subnet, onChange, onDelete, onAddRange, onDeleteRange, canEdit }) {
  const [newRange, setNewRange] = useState({ start_ip: '', end_ip: '' });

  const set = (field) => (e) => onChange({ ...subnet, [field]: e.target.value });
  const usesDhcp = subnet.ip_assignment === 'DHCP' || subnet.ip_assignment === 'Static+DHCP';
  const usesStatic = subnet.ip_assignment === 'Static' || subnet.ip_assignment === 'Static+DHCP';

  return (
    <div className="rounded border border-border bg-canvas p-4">
      <div className="mb-3 flex items-center justify-between">
        <span
          className={`rounded px-2 py-0.5 text-xs font-medium ${
            subnet.level === 'Primary' ? 'bg-primary/10 text-primary' : 'bg-border text-ink-muted'
          }`}
        >
          {subnet.level}
        </span>
        {canEdit && (
          <button onClick={onDelete} className="text-ink-muted hover:text-danger">
            <Trash2 size={16} strokeWidth={1.75} />
          </button>
        )}
      </div>

      <div className="mb-3 grid grid-cols-3 gap-3">
        <label className="block">
          <span className="mb-1 block text-xs text-ink-muted">Network address</span>
          <input
            disabled={!canEdit}
            className="w-full rounded border border-border px-2 py-1.5 text-sm"
            placeholder="192.168.56.0"
            value={subnet.network_address || ''}
            onChange={set('network_address')}
          />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs text-ink-muted">Prefix (/n)</span>
          <input
            disabled={!canEdit}
            type="number"
            min={8}
            max={32}
            className="w-full rounded border border-border px-2 py-1.5 text-sm"
            value={subnet.prefix_len || ''}
            onChange={set('prefix_len')}
          />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs text-ink-muted">Gateway</span>
          <input
            disabled={!canEdit}
            className="w-full rounded border border-border px-2 py-1.5 text-sm"
            placeholder="192.168.56.254"
            value={subnet.gateway || ''}
            onChange={set('gateway')}
          />
        </label>
      </div>

      <div className="mb-3">
        <span className="mb-1 block text-xs text-ink-muted">IP Assignment</span>
        <div className="flex gap-4 text-sm">
          {['Static', 'DHCP', 'Static+DHCP'].map((opt) => (
            <label key={opt} className="flex items-center gap-1.5">
              <input
                type="radio"
                disabled={!canEdit}
                checked={subnet.ip_assignment === opt}
                onChange={() => onChange({ ...subnet, ip_assignment: opt })}
              />
              {opt}
            </label>
          ))}
        </div>
      </div>

      {usesDhcp && (
        <div className="mb-3 grid grid-cols-3 gap-3 rounded border border-warning/30 bg-warning/5 p-3">
          <label className="block">
            <span className="mb-1 block text-xs text-ink-muted">DHCP Server</span>
            <input
              disabled={!canEdit}
              className="w-full rounded border border-border px-2 py-1.5 text-sm"
              value={subnet.dhcp_server || ''}
              onChange={set('dhcp_server')}
            />
          </label>
          <label className="block">
            <span className="mb-1 block text-xs text-ink-muted">DHCP Start</span>
            <input
              disabled={!canEdit}
              className="w-full rounded border border-border px-2 py-1.5 text-sm"
              value={subnet.dhcp_start || ''}
              onChange={set('dhcp_start')}
            />
          </label>
          <label className="block">
            <span className="mb-1 block text-xs text-ink-muted">DHCP End</span>
            <input
              disabled={!canEdit}
              className="w-full rounded border border-border px-2 py-1.5 text-sm"
              value={subnet.dhcp_end || ''}
              onChange={set('dhcp_end')}
            />
          </label>
        </div>
      )}

      {usesStatic && (
        <div>
          <span className="mb-1 block text-xs text-ink-muted">
            Static Ranges ({subnet.static_ranges?.length || 0}) — รองรับได้มากกว่า 1 ช่วง
          </span>
          <div className="space-y-1.5">
            {(subnet.static_ranges || []).map((range) => (
              <div key={range.range_id} className="flex items-center gap-2 text-sm">
                <span className="flex-1 rounded border border-border bg-surface px-2 py-1">
                  {range.start_address} — {range.end_address}
                </span>
                {canEdit && (
                  <button onClick={() => onDeleteRange(range.range_id)} className="text-ink-muted hover:text-danger">
                    <Trash2 size={14} strokeWidth={1.75} />
                  </button>
                )}
              </div>
            ))}
          </div>

          {canEdit && (
            <div className="mt-2 flex items-center gap-2">
              <input
                className="flex-1 rounded border border-border px-2 py-1.5 text-sm"
                placeholder="Start IP"
                value={newRange.start_ip}
                onChange={(e) => setNewRange({ ...newRange, start_ip: e.target.value })}
              />
              <input
                className="flex-1 rounded border border-border px-2 py-1.5 text-sm"
                placeholder="End IP"
                value={newRange.end_ip}
                onChange={(e) => setNewRange({ ...newRange, end_ip: e.target.value })}
              />
              <button
                onClick={() => {
                  onAddRange(newRange);
                  setNewRange({ start_ip: '', end_ip: '' });
                }}
                className="flex items-center gap-1 rounded border border-border px-2 py-1.5 text-sm text-primary hover:bg-primary/5"
              >
                <Plus size={14} strokeWidth={2} />
                เพิ่มช่วง
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
