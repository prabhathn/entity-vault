import { useState } from 'react';
import { enrichIn, getRandomDemoEncodingsBatch } from '../api/client';
import DemoButton from '../components/DemoButton';

export default function EnrichInPage() {
  const [groupName, setGroupName] = useState('');
  const [description, setDescription] = useState('');
  const [entityType, setEntityType] = useState('PRODUCT');
  const [categories, setCategories] = useState('');
  const [namespace, setNamespace] = useState('');
  const [membersText, setMembersText] = useState('');
  const [result, setResult] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleEnrichIn = async () => {
    setLoading(true); setError(''); setResult(null);
    try {
      const categoryValues = categories.split(',').map(s => s.trim()).filter(Boolean);
      const members = membersText.split('\n').map(line => {
        const [encoded_id, category_value] = line.split(',').map(s => s.trim());
        return { encoded_id, category_value: category_value || '' };
      }).filter(m => m.encoded_id);
      const res = await enrichIn({
        group_name: groupName,
        group_description: description,
        entity_type: entityType,
        category_schema: { values: categoryValues },
        namespace_name: namespace,
        members,
      });
      setResult(res.data);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Enrichment In failed');
    } finally { setLoading(false); }
  };

  return (
    <div className="page">
      <h1>Create Group</h1>
      <p>Create a structured entity group and assign members with category values.</p>
      <div className="demo-box">
        <div className="demo-box-header">Demo</div>
        <div className="demo-buttons">
          <DemoButton label="Random Group (100 members)" onClick={async () => { const r = await getRandomDemoEncodingsBatch(100); const d = r.data; const names = ['HIGH_MARGIN_PRODUCTS', 'ECO_FRIENDLY', 'SEASONAL_PICKS', 'TOP_SELLERS', 'CLEARANCE_ITEMS']; const tiers = ['TIER1', 'TIER2', 'TIER3']; setGroupName(names[Math.floor(Math.random() * names.length)] + '_' + Math.random().toString(36).slice(2, 6).toUpperCase()); setDescription('Auto-generated demo group with 100 members'); setEntityType('PRODUCT'); setCategories('TIER1, TIER2, TIER3'); setNamespace(d.namespace); setMembersText(d.encoded_ids.map((id: string) => id + ',' + tiers[Math.floor(Math.random() * tiers.length)]).join('\n')); setResult(null); }} />
        </div>
      </div>
      <div className="form-group">
        <label>Group Name</label>
        <input value={groupName} onChange={(e) => setGroupName(e.target.value)} placeholder="e.g., PREMIUM_ELECTRONICS" />
      </div>
      <div className="form-group">
        <label>Description</label>
        <input value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Group description" />
      </div>
      <div className="form-group">
        <label>Entity Type</label>
        <select value={entityType} onChange={(e) => setEntityType(e.target.value)}>
          <option value="PRODUCT">PRODUCT</option>
          <option value="PERSON">PERSON</option>
          <option value="LOCATION">LOCATION</option>
        </select>
      </div>
      <div className="form-group">
        <label>Category Values (comma-separated)</label>
        <input value={categories} onChange={(e) => setCategories(e.target.value)} placeholder="e.g., TIER1, TIER2, TIER3" />
      </div>
      <div className="form-group">
        <label>Namespace</label>
        <input value={namespace} onChange={(e) => setNamespace(e.target.value)} placeholder="e.g., PARTNER_ALPHA" />
      </div>
      <div className="form-group">
        <label>Members (one per line: encoded_id,category_value)</label>
        <textarea value={membersText} onChange={(e) => setMembersText(e.target.value)} rows={5} placeholder="abc123...,TIER1&#10;def456...,TIER2" />
      </div>
      <button onClick={handleEnrichIn} disabled={loading}>{loading ? 'Creating...' : 'Create Group & Assign'}</button>
      {error && <div className="error">{error}</div>}
      {result && (
        <div className="result">
          <h3>Group Created</h3>
          <table><tbody>
            <tr><td>Group ID</td><td><code>{result.group_id as string}</code></td></tr>
            <tr><td>Members Added</td><td>{result.members_added as number}</td></tr>
            <tr><td>Already Existed</td><td>{result.already_existed as number}</td></tr>
            <tr><td>Unmatched</td><td>{result.unmatched as number}</td></tr>
          </tbody></table>
        </div>
      )}
    </div>
  );
}
