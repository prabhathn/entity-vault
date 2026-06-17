import { useState, useEffect } from 'react';
import { listGroups, requestGroupAccess } from '../api/client';

export default function GroupsPage() {
  const [groups, setGroups] = useState<Record<string, unknown>[]>([]);
  const [loading, setLoading] = useState(false);
  const [accessNs, setAccessNs] = useState('');
  const [message, setMessage] = useState('');
  const [expandedGroup, setExpandedGroup] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    listGroups().then(res => setGroups(res.data || [])).finally(() => setLoading(false));
  }, []);

  const handleRequestAccess = async (groupId: string) => {
    if (!accessNs) { setMessage('Enter a namespace first'); return; }
    try {
      const res = await requestGroupAccess({ group_id: groupId, namespace_name: accessNs });
      setMessage(`Access ${res.data.status} for group ${groupId}`);
    } catch { setMessage('Request failed'); }
  };

  const parseSchema = (val: unknown): Record<string, unknown> | null => {
    if (!val) return null;
    if (typeof val === 'string') { try { return JSON.parse(val); } catch { return null; } }
    return val as Record<string, unknown>;
  };

  return (
    <div className="page">
      <h1>Group Marketplace</h1>
      <p>Browse discoverable entity groups. Request access to view membership.</p>
      <div className="form-group">
        <label>Your Namespace (for access requests)</label>
        <input value={accessNs} onChange={(e) => setAccessNs(e.target.value)} placeholder="e.g., PARTNER_BETA" />
      </div>
      {message && <div className="info">{message}</div>}
      {loading ? <p>Loading...</p> : (
        <table>
          <thead><tr><th>Group Name</th><th>Entity Type</th><th>Description</th><th>Members</th><th>Created By</th><th></th><th></th></tr></thead>
          <tbody>
            {groups.map((g, i) => {
              const groupId = g.group_id as string;
              const isExpanded = expandedGroup === groupId;
              const categorySchema = parseSchema(g.category_schema);
              const categoryValues = (categorySchema?.values || []) as string[];
              return (
                <>
                  <tr key={i}>
                    <td><strong>{g.group_name as string}</strong></td>
                    <td>{g.entity_type as string}</td>
                    <td>{(g.group_description as string)?.slice(0, 40) || '-'}</td>
                    <td>{g.member_count as number}</td>
                    <td>{g.created_by as string}</td>
                    <td><button onClick={() => setExpandedGroup(isExpanded ? null : groupId)}>Info</button></td>
                    <td><button onClick={() => handleRequestAccess(groupId)}>Request Access</button></td>
                  </tr>
                  {isExpanded && (
                    <tr key={groupId + '-detail'} className="audit-detail-row">
                      <td colSpan={7}>
                        <div className="audit-detail">
                          <div className="audit-detail-section" style={{ flex: 2 }}>
                            <h4>Description</h4>
                            <p style={{ fontSize: '13px', color: 'var(--text)' }}>{g.group_description as string || 'No description'}</p>
                          </div>
                          <div className="audit-detail-section">
                            <h4>Category Schema</h4>
                            {categoryValues.length > 0 ? (
                              <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
                                {categoryValues.map((v, vi) => (
                                  <span key={vi} style={{ padding: '3px 8px', background: 'var(--bg)', borderRadius: '3px', fontSize: '12px', border: '1px solid var(--border)' }}>{v}</span>
                                ))}
                              </div>
                            ) : (
                              <pre style={{ fontSize: '11px' }}>{JSON.stringify(categorySchema, null, 2)}</pre>
                            )}
                          </div>
                          <div className="audit-detail-section">
                            <h4>Stats</h4>
                            <p style={{ fontSize: '13px' }}>Members: {g.member_count as number}</p>
                            <p style={{ fontSize: '13px' }}>Created: {(g.created_at as string)?.slice(0, 10) || '-'}</p>
                            <p style={{ fontSize: '13px' }}>Group ID: <code>{groupId.slice(0, 12)}...</code></p>
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
