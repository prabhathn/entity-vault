import { useState, useEffect } from 'react';
import { listEntities, getEntity } from '../api/client';
import CopyButton from '../components/CopyButton';

export default function EntitiesPage() {
  const PAGE_SIZE = 50;
  const [entities, setEntities] = useState<Record<string, unknown>[]>([]);
  const [total, setTotal] = useState(0);
  const [selected, setSelected] = useState<Record<string, unknown> | null>(null);
  const [search, setSearch] = useState('');
  const [activeSearch, setActiveSearch] = useState('');
  const [loading, setLoading] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);
  const [offset, setOffset] = useState(0);

  const fetchEntities = async (newOffset = 0, searchTerm?: string) => {
    setLoading(true);
    const term = searchTerm !== undefined ? searchTerm : search;
    try {
      const res = await listEntities({ search: term || undefined, limit: PAGE_SIZE, offset: newOffset });
      setEntities(res.data.rows);
      setTotal(res.data.total);
      setOffset(newOffset);
      setActiveSearch(term);
    } finally { setLoading(false); }
  };

  useEffect(() => { fetchEntities(); }, []);

  const handleSearch = () => {
    fetchEntities(0, search);
  };

  const clearSearch = () => {
    setSearch('');
    fetchEntities(0, '');
  };

  const handleSelect = async (entityId: string) => {
    setDetailLoading(true);
    setSelected(null);
    try {
      const res = await getEntity(entityId);
      setSelected(res.data);
    } finally { setDetailLoading(false); }
  };

  return (
    <div className="page">
      <h1>Entity Browser</h1>
      <div className="form-group" style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
          placeholder="Search metadata..."
          style={{ flex: 1 }}
        />
        <button onClick={handleSearch}>Search</button>
        {activeSearch && (
          <button onClick={clearSearch} className="clear-btn" title="Clear search">X</button>
        )}
      </div>

      {activeSearch && (
        <div className="search-indicator">
          Showing results for: <strong>"{activeSearch}"</strong>
          <span className="search-count">{total.toLocaleString()} result{total !== 1 ? 's' : ''}</span>
        </div>
      )}
      {!activeSearch && !loading && (
        <div className="search-count-bar">
          {total.toLocaleString()} total entities
        </div>
      )}

      {loading && <p>Loading...</p>}
      <div style={{ display: 'flex', gap: '24px', alignItems: 'flex-start' }}>
        <div style={{ width: '420px', flexShrink: 0 }}>
          <table>
            <thead><tr><th>Entity ID</th><th>Type</th><th>State</th><th>Created</th></tr></thead>
            <tbody>
              {entities.map((e) => (
                <tr key={e.entity_id as string} onClick={() => handleSelect(e.entity_id as string)} style={{ cursor: 'pointer' }}>
                  <td><code>{(e.entity_id as string)?.slice(0, 12)}...</code></td>
                  <td>{e.entity_type as string}</td>
                  <td><span className="badge-active">{(e as Record<string, unknown>).lifecycle_state as string || 'ACTIVE'}</span></td>
                  <td>{(e.created_at as string)?.slice(0, 10) || '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '12px', fontSize: '13px' }}>
            <button onClick={() => fetchEntities(offset - PAGE_SIZE)} disabled={offset === 0}>Previous</button>
            <span style={{ color: 'var(--text-muted)' }}>
              {offset + 1}–{offset + entities.length} of {total.toLocaleString()}
            </span>
            <button onClick={() => fetchEntities(offset + PAGE_SIZE)} disabled={entities.length < PAGE_SIZE}>Next</button>
          </div>
        </div>
        <div style={{ flex: 1, minWidth: 0, position: 'sticky', top: '32px', alignSelf: 'flex-start', maxHeight: 'calc(100vh - 80px)', overflowY: 'auto' }}>
          {detailLoading && (
            <div className="result">
              <div className="loading-indicator">Loading entity details...</div>
            </div>
          )}
          {selected && !detailLoading && (
            <div className="result">
              <h3>Entity Detail</h3>
              <div className="detail-header">
                <p><strong>ID:</strong> <code>{selected.entity_id as string}</code><CopyButton value={selected.entity_id as string} /></p>
                <p><strong>Type:</strong> {selected.entity_type as string}</p>
                <p><strong>State:</strong> <span className="badge-active">{selected.lifecycle_state as string}</span></p>
                <p><strong>Trust Tier:</strong> {selected.trust_tier as string || 'STANDARD'}</p>
              </div>

              <h4>Metadata</h4>
              <div className="metadata-grid">
                {!!selected.metadata && Object.entries(
                  typeof selected.metadata === 'string' ? JSON.parse(selected.metadata) : selected.metadata as Record<string, unknown>
                ).map(([key, value]) => (
                  <div className="metadata-row" key={key}>
                    <span className="metadata-key">{key}</span>
                    <span className="metadata-value">{value != null ? String(value) : <em>null</em>}</span>
                  </div>
                ))}
              </div>

              <h4>Identifiers ({((selected.identifiers as unknown[]) || []).length})</h4>
              <div className="identifiers-list">
                {((selected.identifiers as Record<string, unknown>[]) || []).map((id, i) => (
                  <div className="identifier-item" key={i}>
                    <span className="identifier-type">{id.identifier_type as string}</span>
                    <span className="identifier-value">{id.identifier_value as string || '(hashed)'}</span>
                    <span className="identifier-confidence">{((id.confidence_score as number) * 100).toFixed(0)}%</span>
                    {(id.identifier_value as string) && <CopyButton value={id.identifier_value as string} />}
                  </div>
                ))}
              </div>

              <h4>Encodings ({((selected.encodings as unknown[]) || []).length})</h4>
              {((selected.encodings as Record<string, unknown>[]) || []).length > 0 ? (
                <div className="identifiers-list">
                  {((selected.encodings as Record<string, unknown>[]) || []).map((enc, i) => (
                    <div className="identifier-item" key={i}>
                      <span className="identifier-type">{enc.namespace_name as string}</span>
                      <code className="identifier-value">{(enc.encoded_id as string)?.slice(0, 24)}...</code>
                      <CopyButton value={enc.encoded_id as string} />
                    </div>
                  ))}
                </div>
              ) : (
                <p className="empty-state">No encodings yet</p>
              )}

              {((selected.groups as unknown[]) || []).length > 0 && (
                <>
                  <h4>Groups ({((selected.groups as unknown[]) || []).length})</h4>
                  <div className="identifiers-list">
                    {((selected.groups as Record<string, unknown>[]) || []).map((g, i) => (
                      <div className="identifier-item" key={i}>
                        <span className="identifier-type">{g.group_name as string}</span>
                        <span className="identifier-value">{g.category_value as string || '-'}</span>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </div>
          )}
          {!selected && !detailLoading && (
            <div className="result empty-state">
              <p>Click an entity to view details</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
