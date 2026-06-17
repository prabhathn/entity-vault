import { useState } from 'react';
import { transcodeEntity, getRandomDemoEncoding } from '../api/client';
import DemoButton from '../components/DemoButton';

export default function TranscodePage() {
  const [encodedId, setEncodedId] = useState('');
  const [sourceNs, setSourceNs] = useState('');
  const [targetNs, setTargetNs] = useState('');
  const [result, setResult] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleTranscode = async () => {
    setLoading(true); setError(''); setResult(null);
    try {
      const res = await transcodeEntity({ encoded_id: encodedId, source_namespace: sourceNs, target_namespace: targetNs });
      setResult(res.data);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Transcoding failed');
    } finally { setLoading(false); }
  };

  return (
    <div className="page">
      <h1>Transcode</h1>
      <p>Convert an encoded ID from one partner's namespace to another (policy-gated).</p>
      <div className="demo-box">
        <div className="demo-box-header">Demo</div>
        <div className="demo-buttons">
          <DemoButton label="Random Transcode" onClick={async () => { const r = await getRandomDemoEncoding(); const d = r.data; setEncodedId(d.encoded_id); setSourceNs(d.source_namespace); setTargetNs(d.target_namespaces?.[0] || 'PARTNER_BETA'); setResult(null); }} />
        </div>
      </div>
      <div className="form-group">
        <label>Encoded ID (Source)</label>
        <input value={encodedId} onChange={(e) => setEncodedId(e.target.value)} placeholder="Source encoded ID" />
      </div>
      <div className="form-group">
        <label>Source Namespace</label>
        <input value={sourceNs} onChange={(e) => setSourceNs(e.target.value)} placeholder="e.g., PARTNER_ALPHA" />
      </div>
      <div className="form-group">
        <label>Target Namespace</label>
        <input value={targetNs} onChange={(e) => setTargetNs(e.target.value)} placeholder="e.g., PARTNER_BETA" />
      </div>
      <button onClick={handleTranscode} disabled={loading}>{loading ? 'Transcoding...' : 'Transcode'}</button>
      {error && <div className="error">{error}</div>}
      {result && (
        <div className="result">
          <h3>Transcode Result</h3>
          <table><tbody>
            <tr><td>Target Encoded ID</td><td><code>{result.target_encoded_id as string}</code></td></tr>
            <tr><td>Source Namespace</td><td>{result.source_namespace as string}</td></tr>
            <tr><td>Target Namespace</td><td>{result.target_namespace as string}</td></tr>
            <tr><td>Policy Result</td><td><span className="badge-success">{result.policy_result as string}</span></td></tr>
          </tbody></table>
        </div>
      )}
    </div>
  );
}
