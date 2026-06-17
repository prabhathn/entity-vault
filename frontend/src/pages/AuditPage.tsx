import { useState, useEffect } from 'react';
import { getAuditLog } from '../api/client';

export default function AuditPage() {
  const [logs, setLogs] = useState<Record<string, unknown>[]>([]);
  const [operation, setOperation] = useState('');
  const [loading, setLoading] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);

  const fetchLogs = () => {
    setLoading(true);
    getAuditLog({ operation: operation || undefined, limit: 100 })
      .then(res => setLogs(res.data))
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchLogs(); }, []);

  const toggleExpand = (auditId: string) => {
    setExpanded(expanded === auditId ? null : auditId);
  };

  const parseVariant = (val: unknown): Record<string, unknown> | null => {
    if (!val) return null;
    if (typeof val === 'string') {
      try { return JSON.parse(val); } catch { return null; }
    }
    return val as Record<string, unknown>;
  };

  return (
    <div className="page">
      <h1>Audit Log</h1>
      <div className="form-group" style={{ display: 'flex', gap: '8px' }}>
        <select value={operation} onChange={(e) => setOperation(e.target.value)}>
          <option value="">All Operations</option>
          <option value="RESOLVE">RESOLVE</option>
          <option value="ENCODE">ENCODE</option>
          <option value="TRANSCODE">TRANSCODE</option>
          <option value="ENRICH_OUT">ENRICH_OUT</option>
          <option value="ENRICH_IN">ENRICH_IN</option>
          <option value="GROUP_ACCESS_GRANT">GROUP_ACCESS_GRANT</option>
        </select>
        <button onClick={fetchLogs}>Filter</button>
      </div>
      {loading ? <p>Loading...</p> : (
        <table>
          <thead><tr><th>Time</th><th>Operation</th><th>Entity ID</th><th>Tier</th><th>Confidence</th><th>Policy</th><th>User</th><th></th></tr></thead>
          <tbody>
            {logs.map((log) => {
              const auditId = log.audit_id as string;
              const isExpanded = expanded === auditId;
              return (
                <>
                  <tr key={auditId} onClick={() => toggleExpand(auditId)} style={{ cursor: 'pointer' }}>
                    <td>{(log.performed_at as string) || '-'}</td>
                    <td><span className={`op-${(log.operation as string || '').toLowerCase()}`}>{log.operation as string}</span></td>
                    <td><code>{(log.entity_id as string)?.slice(0, 8) || '-'}...</code></td>
                    <td>{log.resolution_tier as string || '-'}</td>
                    <td>{log.confidence_score != null ? `${((log.confidence_score as number) * 100).toFixed(0)}%` : '-'}</td>
                    <td>{log.policy_result as string || '-'}</td>
                    <td>{log.performed_by as string}</td>
                    <td>{isExpanded ? '\u25B2' : '\u25BC'}</td>
                  </tr>
                  {isExpanded && (
                    <tr key={auditId + '-detail'} className="audit-detail-row">
                      <td colSpan={8}>
                        <div className="audit-detail">
                          <div className="audit-detail-section">
                            <h4>Input Data</h4>
                            <pre>{JSON.stringify(parseVariant(log.input_data), null, 2) || 'None'}</pre>
                          </div>
                          <div className="audit-detail-section">
                            <h4>Output Data</h4>
                            <pre>{JSON.stringify(parseVariant(log.output_data), null, 2) || 'None'}</pre>
                          </div>
                          {!!log.alternatives && (
                            <div className="audit-detail-section">
                              <h4>Alternatives</h4>
                              <pre>{JSON.stringify(parseVariant(log.alternatives), null, 2)}</pre>
                            </div>
                          )}
                          <div className="audit-detail-meta">
                            {!!log.namespace_id && <span>Namespace: <code>{(log.namespace_id as string)?.slice(0, 8)}...</code></span>}
                            {!!log.target_namespace_id && <span>Target NS: <code>{(log.target_namespace_id as string)?.slice(0, 8)}...</code></span>}
                            {!!log.group_id && <span>Group: <code>{(log.group_id as string)?.slice(0, 8)}...</code></span>}
                          </div>
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
  );
}
