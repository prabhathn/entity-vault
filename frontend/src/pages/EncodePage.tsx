import { useState } from 'react';
import { encodeEntity, getRandomDemoEntity } from '../api/client';
import DemoButton from '../components/DemoButton';

export default function EncodePage() {
  const [entityId, setEntityId] = useState('');
  const [namespace, setNamespace] = useState('');
  const [result, setResult] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleEncode = async () => {
    setLoading(true); setError(''); setResult(null);
    try {
      const res = await encodeEntity({ entity_id: entityId, namespace_name: namespace });
      setResult(res.data);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Encoding failed');
    } finally { setLoading(false); }
  };

  return (
    <div className="page">
      <h1>Encode Entity</h1>
      <p>Generate a partner-specific encoded ID for an entity.</p>
      <div className="demo-box">
        <div className="demo-box-header">Demo</div>
        <div className="demo-buttons">
          <DemoButton label="Encode for Alpha" onClick={async () => { const r = await getRandomDemoEntity(); setEntityId(r.data.entity_id); setNamespace('PARTNER_ALPHA'); setResult(null); }} />
          <DemoButton label="Encode for Beta" onClick={async () => { const r = await getRandomDemoEntity(); setEntityId(r.data.entity_id); setNamespace('PARTNER_BETA'); setResult(null); }} />
        </div>
      </div>
      <div className="form-group">
        <label>Entity ID</label>
        <input value={entityId} onChange={(e) => setEntityId(e.target.value)} placeholder="Entity UUID" />
      </div>
      <div className="form-group">
        <label>Namespace</label>
        <input value={namespace} onChange={(e) => setNamespace(e.target.value)} placeholder="e.g., PARTNER_ALPHA" />
      </div>
      <button onClick={handleEncode} disabled={loading}>{loading ? 'Encoding...' : 'Encode'}</button>
      {error && <div className="error">{error}</div>}
      {result && (
        <div className="result">
          <h3>Encoding Result</h3>
          <table><tbody>
            <tr><td>Encoded ID</td><td><code>{result.encoded_id as string}</code></td></tr>
            <tr><td>Namespace</td><td>{result.namespace as string}</td></tr>
            <tr><td>Cached</td><td>{result.cached ? 'Yes' : 'No (newly generated)'}</td></tr>
          </tbody></table>
        </div>
      )}
    </div>
  );
}
