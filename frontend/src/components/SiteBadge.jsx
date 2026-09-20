const SITE_STYLES = {
  '1st Site': 'bg-site1/10 text-site1',
  '2nd Site': 'bg-site2/10 text-site2',
};

/** Renders the org's two fixed sites as a colored pill — see the Design
 * System notes: 1st Site is blue, 2nd Site is purple, consistently across
 * every list/table that carries a site column.
 */
export default function SiteBadge({ siteName }) {
  const cls = SITE_STYLES[siteName] || 'bg-border text-ink-muted';
  return (
    <span className={`inline-flex items-center rounded px-2 py-0.5 text-xs font-medium ${cls}`}>
      {siteName || 'ไม่ระบุ'}
    </span>
  );
}
