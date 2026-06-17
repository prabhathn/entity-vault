import { useState, useMemo } from 'react';
import { resolveEntity, getRandomDemoEntity } from '../api/client';
import CopyButton from '../components/CopyButton';
import DemoButton from '../components/DemoButton';

type ResolveMode = 'identifier' | 'metadata';

const IDENTIFIER_FIELDS: Record<string, string> = {
  i_item_id: 'ITEM_ID',
  i_item_sk: 'ITEM_SK',
  c_customer_id: 'CUSTOMER_ID',
  c_email_address: 'EMAIL',
  s_store_id: 'STORE_ID',
  upc: 'UPC',
  sku: 'SKU',
};

export default function ResolvePage() {
  const [entityType, setEntityType] = useState('PRODUCT');
  const [mode, setMode] = useState<ResolveMode>('identifier');
  const [identifierType, setIdentifierType] = useState('ITEM_ID');
  const [identifierValue, setIdentifierValue] = useState('');
  const [metadataJson, setMetadataJson] = useState('');
  const [extractIdentifiers, setExtractIdentifiers] = useState(true);
  const [result, setResult] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // Detect identifier fields in the metadata JSON
  const detectedIdentifiers = useMemo(() => {
    if (mode !== 'metadata' || !metadataJson) return [];
    try {
      const parsed = JSON.parse(metadataJson);
      return Object.entries(parsed)
        .filter(([key]) => key.toLowerCase() in IDENTIFIER_FIELDS)
        .map(([key, value]) => ({ field: key, type: IDENTIFIER_FIELDS[key.toLowerCase()], value: String(value) }));
    } catch {
      return [];
    }
  }, [metadataJson, mode]);

  const handleResolve = async () => {
    setLoading(true);
    setError('');
    setResult(null);
    try {
      let identifiers: { type: string; value: string }[] | undefined;
      let metadata: Record<string, unknown> | undefined;

      if (mode === 'identifier') {
        identifiers = identifierValue ? [{ type: identifierType, value: identifierValue }] : undefined;
      } else {
        const parsed = metadataJson ? JSON.parse(metadataJson) : undefined;
        if (parsed && extractIdentifiers && detectedIdentifiers.length > 0) {
          // Extract identifier fields and send them as proper identifiers
          identifiers = detectedIdentifiers.map(d => ({ type: d.type, value: d.value }));
          // Remove identifier fields from metadata (leave only descriptors)
          const metadataOnly = { ...parsed };
          for (const d of detectedIdentifiers) {
            delete metadataOnly[d.field];
          }
          metadata = Object.keys(metadataOnly).length > 0 ? metadataOnly : undefined;
        } else {
          metadata = parsed;
        }
      }

      const strategy = mode === 'identifier' ? 'EXACT_ONLY' : 'AUTO';
      const res = await resolveEntity({ entity_type: entityType, identifiers, metadata, strategy });
      setResult(res.data);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Resolution failed';
      setError(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="page">
      <h1>Resolve Entity</h1>
      <p>Find an entity by identifier or metadata, or create a new one if not found.</p>

      <div className="form-group">
        <label>Entity Type</label>
        <select value={entityType} onChange={(e) => setEntityType(e.target.value)}>
          <option value="PRODUCT">PRODUCT</option>
          <option value="PERSON">PERSON</option>
          <option value="LOCATION">LOCATION</option>
        </select>
      </div>

      <div className="demo-box">
        <div className="demo-box-header">Demo</div>
        <div className="demo-buttons">
          <DemoButton label="Exact Match" onClick={async () => { const r = await getRandomDemoEntity(); const d = r.data; setMode('identifier'); setIdentifierType(d.exact_match.identifier_type); setIdentifierValue(d.exact_match.identifier_value); setResult(null); }} />
          <DemoButton label="Fuzzy Match" onClick={async () => { const r = await getRandomDemoEntity(); const d = r.data; setMode('metadata'); setMetadataJson(JSON.stringify(d.fuzzy_match.metadata, null, 2)); setResult(null); }} />
          <DemoButton label="Mixed" onClick={async () => { const r = await getRandomDemoEntity(); const d = r.data; setMode('metadata'); setMetadataJson(JSON.stringify(d.mixed_match.metadata, null, 2)); setExtractIdentifiers(true); setResult(null); }} />
        </div>
      </div>

      <div className="form-group">
        <label>Resolve By</label>
        <div className="toggle-group">
          <button
            className={`toggle-btn ${mode === 'identifier' ? 'active' : ''}`}
            onClick={() => setMode('identifier')}
          >
            Identifier
          </button>
          <button
            className={`toggle-btn ${mode === 'metadata' ? 'active' : ''}`}
            onClick={() => setMode('metadata')}
          >
            Metadata
          </button>
        </div>
      </div>

      {mode === 'identifier' && (
        <>
          <div className="form-group">
            <label>Identifier Type</label>
            <input value={identifierType} onChange={(e) => setIdentifierType(e.target.value)} placeholder="e.g., ITEM_ID" />
          </div>
          <div className="form-group">
            <label>Identifier Value</label>
            <input value={identifierValue} onChange={(e) => setIdentifierValue(e.target.value)} placeholder="e.g., AAAAAAAADFKHDAAA" />
          </div>
        </>
      )}

      {mode === 'metadata' && (
        <>
          <div className="form-group">
            <label>Metadata (JSON)</label>
            <textarea value={metadataJson} onChange={(e) => setMetadataJson(e.target.value)} placeholder='{"i_item_id": "AAAAAAAADFKHDAAA", "i_brand": "importonameless #4", "i_category": "Sports"}' rows={5} />
          </div>

          {detectedIdentifiers.length > 0 && (
            <div className="callout">
              <div className="callout-header">
                <strong>Identifier fields detected</strong>
                <label className="toggle-inline">
                  <input type="checkbox" checked={extractIdentifiers} onChange={(e) => setExtractIdentifiers(e.target.checked)} />
                  Extract for exact matching
                </label>
              </div>
              <p className="callout-desc">
                These fields will be used for Tier 1 (exact hash) resolution first, with remaining fields used for fuzzy matching.
              </p>
              <div className="identifiers-list">
                {detectedIdentifiers.map((d, i) => (
                  <div className="identifier-item" key={i}>
                    <span className="identifier-type">{d.type}</span>
                    <span className="identifier-value">{d.value}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </>
      )}

      <button onClick={handleResolve} disabled={loading}>
        {loading ? 'Resolving...' : 'Resolve'}
      </button>

      {error && <div className="error">{error}</div>}

      {result && (
        <div className="result">
          <h3>Resolution Result</h3>
          <table>
            <tbody>
              <tr><td>Entity ID</td><td><code>{result.entity_id as string}</code> <CopyButton value={result.entity_id as string} /></td></tr>
              <tr><td>Resolution Tier</td><td><span className={`tier tier-${(result.resolution_tier as string || '').toLowerCase()}`}>{result.resolution_tier as string}</span></td></tr>
              <tr><td>Confidence</td><td>{result.confidence != null ? `${((result.confidence as number) * 100).toFixed(1)}%` : 'N/A'}</td></tr>
              <tr><td>Is New</td><td>{result.is_new ? 'Yes (created)' : 'No (existing)'}</td></tr>
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
