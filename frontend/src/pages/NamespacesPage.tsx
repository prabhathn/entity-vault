import { useState, useEffect } from 'react';
import { listNamespaces, createNamespace, getNamespaceDetail } from '../api/client';
import CopyButton from '../components/CopyButton';

export default function NamespacesPage() {
  const [namespaces, setNamespaces] = useState<Record<string, unknown>[]>([]);
  const [name, setName] = useState('');
  const [desc, setDesc] = useState('');
  const [org, setOrg] = useState('');
  const [clearance, setClearance] = useState('ENRICHMENT');
  const [message, setMessage] = useState('');
  const [selectedNs, setSelectedNs] = useState<string | null>(null);
  const [detail, setDetail] = useState<Record<string, unknown> | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const fetchNamespaces = () => {
    listNamespaces().then(res => setNamespaces(res.data));
  };

  useEffect(() => { fetchNamespaces(); }, []);

  const handleCreate = async () => {
    try {
      await createNamespace({ namespace_name: name, description: desc, owner_org: org, clearance_level: clearance });
      setMessage(`Namespace "${name}" created`);
      setName(''); setDesc(''); setOrg('');
      fetchNamespaces();
    } catch { setMessage('Creation failed'); }
  };

  const handleSelectNs = async (nsName: string) => {
    setSelectedNs(nsName);
    setDetailLoading(true);
    setDetail(null);
    try {
      const res = await getNamespaceDetail(nsName);
      setDetail(res.data);
    } finally { setDetailLoading(false); }
  };

  const stats = detail?.stats as Record<string, unknown> | undefined;
  const tierBreakdown = (stats?.tier_breakdown || []) as Record<string, unknown>[];
  const totalEncodings = (stats?.total_encodings || 0) as number;
  const encodings = (detail?.encodings || []) as Record<string, unknown>[];

  return (
    <div className="page">
      <h1>Namespace Management</h1>

      {/* Create form */}
      <div className="result" style={{ marginBottom: '24px' }}>
        <h3>Create Namespace</h3>
        <div style={{ display: 'flex', gap: '12px', alignItems: 'flex-end', flexWrap: 'wrap' }}>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Name</label>
            <input value={name} onChange={(e) => setName(e.target.value)} style={{ width: '160px' }} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Description</label>
            <input value={desc} onChange={(e) => setDesc(e.target.value)} style={{ width: '200px' }} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Owner Org</label>
            <input value={org} onChange={(e) => setOrg(e.target.value)} style={{ width: '140px' }} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Clearance</label>
            <select value={clearance} onChange={(e) => setClearance(e.target.value)} style={{ width: '160px' }}>
              <option value="ENRICHMENT">ENRICHMENT</option>
              <option value="IDENTIFIABLE">IDENTIFIABLE</option>
              <option value="INTERNAL">INTERNAL</option>
            </select>
          </div>
          <button onClick={handleCreate}>Create</button>
        </div>
        {message && <div className="info" style={{ marginTop: '8px' }}>{message}</div>}
      </div>

      {/* Main layout: namespace table + detail panel */}
      <div style={{ display: 'flex', gap: '24px', alignItems: 'flex-start' }}>
        <div style={{ width: '500px', flexShrink: 0 }}>
          <h3>Namespaces</h3>
          <table>
            <thead><tr><th>Name</th><th>Org</th><th>Clearance</th><th>Encodings</th><th>Status</th></tr></thead>
            <tbody>
              {namespaces.map((ns, i) => (
                <tr key={i} onClick={() => handleSelectNs(ns.namespace_name as string)} style={{ cursor: 'pointer', background: selectedNs === ns.namespace_name ? 'rgba(41,181,232,0.1)' : undefined }}>
                  <td><strong>{ns.namespace_name as string}</strong></td>
                  <td>{ns.owner_org as string || '-'}</td>
                  <td>{ns.clearance_level as string}</td>
                  <td>{ns.encoding_count as number}</td>
                  <td>{ns.status as string}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div style={{ flex: 1, minWidth: 0, position: 'sticky', top: '32px', alignSelf: 'flex-start', maxHeight: 'calc(100vh - 80px)', overflowY: 'auto' }}>
          {detailLoading && (
            <div className="result">
              <div className="loading-indicator">Loading namespace details...</div>
            </div>
          )}
          {detail && !detailLoading && (
            <div className="result">
              <h3>{selectedNs} — Partner View</h3>

              {/* Stats */}
              <div style={{ display: 'flex', gap: '16px', marginBottom: '20px', flexWrap: 'wrap' }}>
                <div className="stat-card">
                  <div className="stat-value">{totalEncodings.toLocaleString()}</div>
                  <div className="stat-label">Total Encoded Entities</div>
                </div>
                {tierBreakdown.map((tier, i) => (
                  <div className="stat-card" key={i}>
                    <div className="stat-value">
                      {totalEncodings > 0
                        ? `${((tier.cnt as number / totalEncodings) * 100).toFixed(1)}%`
                        : '0%'}
                    </div>
                    <div className="stat-label">{tier.resolution_tier as string}</div>
                    <div className="stat-sub">
                      {tier.cnt as number} entities
                      {tier.avg_confidence != null && ` · avg ${((tier.avg_confidence as number) * 100).toFixed(0)}% conf`}
                    </div>
                  </div>
                ))}
              </div>

              {/* Encodings list */}
              <h4>Encoded IDs ({totalEncodings})</h4>
              {encodings.length > 0 ? (
                <table>
                  <thead><tr><th>Encoded ID</th><th>Entity ID</th><th>Created</th><th></th></tr></thead>
                  <tbody>
                    {encodings.map((enc, i) => (
                      <tr key={i}>
                        <td><code>{(enc.encoded_id as string)?.slice(0, 20)}...</code><CopyButton value={enc.encoded_id as string} /></td>
                        <td><code>{(enc.entity_id as string)?.slice(0, 12)}...</code><CopyButton value={enc.entity_id as string} /></td>
                        <td>{enc.created_at as string}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : (
                <p className="empty-state">No entities encoded for this namespace yet</p>
              )}
            </div>
          )}
          {!detail && !detailLoading && (
            <div className="result empty-state">
              <p>Click a namespace to view partner details and encoded entities</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
