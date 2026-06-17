import { useState } from 'react';
import { enrichOut, getRandomDemoEncodingsBatch } from '../api/client';
import DemoButton from '../components/DemoButton';

export default function EnrichOutPage() {
  const [encodedIds, setEncodedIds] = useState('');
  const [namespace, setNamespace] = useState('');
  const [result, setResult] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleEnrich = async () => {
    setLoading(true); setError(''); setResult(null);
    try {
      const ids = encodedIds.split('\n').map(s => s.trim()).filter(Boolean);
      const res = await enrichOut({ encoded_ids: ids, namespace_name: namespace });
      setResult(res.data);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Enrichment failed');
    } finally { setLoading(false); }
  };

  const summary = result?.summary as Record<string, number> | undefined;
  const results = (result?.results || []) as Array<Record<string, unknown>>;

  return (
    <div className="page">
      <h1>Enrichment Out</h1>
      <p>Send encoded IDs to receive back authorized metadata based on your clearance level.</p>
      <div className="demo-box">
        <div className="demo-box-header">Demo</div>
        <div className="demo-buttons">
          <DemoButton label="100 IDs (90 match + 10 fake)" onClick={async () => { const r = await getRandomDemoEncodingsBatch(90); const d = r.data; const fakes = Array.from({length: 10}, () => 'fake_id_' + Math.random().toString(36).slice(2, 14)); setEncodedIds([...d.encoded_ids, ...fakes].join('\n')); setNamespace(d.namespace); setResult(null); }} />
        </div>
      </div>
      <div className="form-group">
        <label>Encoded IDs (one per line)</label>
        <textarea value={encodedIds} onChange={(e) => setEncodedIds(e.target.value)} rows={5} placeholder="Paste encoded IDs here, one per line" />
      </div>
      <div className="form-group">
        <label>Namespace</label>
        <input value={namespace} onChange={(e) => setNamespace(e.target.value)} placeholder="e.g., PARTNER_ALPHA" />
      </div>
      <button onClick={handleEnrich} disabled={loading}>{loading ? 'Enriching...' : 'Enrich'}</button>
      {error && <div className="error">{error}</div>}
      {summary && (
        <div className="result">
          <h3>Summary</h3>
          <p>Total: {summary.total} | Matched: {summary.matched} | Unmatched: {summary.unmatched}</p>
          <h3>Results</h3>
          <table>
            <thead><tr><th>Encoded ID</th><th>Matched</th><th>Metadata</th></tr></thead>
            <tbody>
              {results.map((r, i) => (
                <tr key={i}>
                  <td><code>{(r.encoded_id as string)?.slice(0, 16)}...</code></td>
                  <td>{r.matched ? 'Yes' : 'No'}</td>
                  <td>{r.metadata ? JSON.stringify(r.metadata).slice(0, 80) + '...' : '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
