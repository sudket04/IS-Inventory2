/** The site selector required on every data-entry form (per the project's
 * site-scoping rule): only the org's two real sites, never a free-text
 * field, so a form can never save without resolving to a site. `siteOptions`
 * comes from GET /api/records/locations filtered to level = 'Site' — this
 * component doesn't hardcode the two names, it only enforces "pick one".
 */
export default function SiteSelect({ value, onChange, siteOptions, required = true }) {
  return (
    <label className="block">
      <span className="mb-1 block text-sm font-medium text-ink">
        Site {required && <span className="text-danger">*</span>}
      </span>
      <select
        className="w-full rounded border border-border px-3 py-2 text-sm focus:border-primary focus:outline-none"
        value={value || ''}
        onChange={(e) => onChange(e.target.value)}
        required={required}
      >
        <option value="" disabled>
          -- เลือก Site --
        </option>
        {siteOptions.map((site) => (
          <option key={site.location_id} value={site.location_id}>
            {site.name}
          </option>
        ))}
      </select>
    </label>
  );
}
