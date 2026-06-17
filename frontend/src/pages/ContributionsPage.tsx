import { useState, useEffect } from 'react';
import { createContributionSchema, listContributionSchemas, submitContributions, requestContributionAccess, getRandomDemoEncodingsBatch } from '../api/client';
import DemoButton from '../components/DemoButton';

export default function ContributionsPage() {
  const [tab, setTab] = useState<'define' | 'submit' | 'browse'>('browse');

  // Define schema state
  const [schemaName, setSchemaName] = useState('');
  const [schemaDesc, setSchemaDesc] = useState('');
  const [schemaEntityType, setSchemaEntityType] = useState('PRODUCT');
  const [schemaNamespace, setSchemaNamespace] = useState('');
  const [fieldsText, setFieldsText] = useState('');
  const [defineResult, setDefineResult] = useState<Record<string, unknown> | null>(null);

  // Submit state
  const [submitSchemaName, setSubmitSchemaName] = useState('');
  const [submitNamespace, setSubmitNamespace] = useState('');
  const [contributionsText, setContributionsText] = useState('');
  const [submitResult, setSubmitResult] = useState<Record<string, unknown> | null>(null);

  // Browse state
  const [schemas, setSchemas] = useState<Record<string, unknown>[]>([]);
  const [accessNs, setAccessNs] = useState('');
  const [message, setMessage] = useState('');
  const [loading, setLoading] = useState(false);
  const [expandedSchema, setExpandedSchema] = useState<string | null>(null);

  const fetchSchemas = () => {
    setLoading(true);
    listContributionSchemas().then(res => {
      setSchemas(Array.isArray(res.data) ? res.data : []);
    }).finally(() => setLoading(false));
  };

  useEffect(() => { fetchSchemas(); }, []);

  const handleDefineSchema = async () => {
    const fields = fieldsText.split('\n').filter(Boolean).map(line => {
      const [name, type, description] = line.split(',').map(s => s.trim());
      return { name, type: type || 'VARCHAR', description: description || '' };
    });
    try {
      const res = await createContributionSchema({
        schema_name: schemaName, description: schemaDesc,
        entity_type: schemaEntityType, namespace_name: schemaNamespace,
        field_definitions: fields,
      });
      setDefineResult(res.data);
      fetchSchemas();
    } catch (err) {
      setDefineResult({ error: 'Failed to create schema' });
    }
  };

  const handleSubmit = async () => {
    try {
      const contributions = contributionsText.split('\n').filter(Boolean).map(line => {
        const firstComma = line.indexOf(',');
        const encoded_id = line.slice(0, firstComma).trim();
        const attrJson = line.slice(firstComma + 1).trim();
        return { encoded_id, attributes: JSON.parse(attrJson) };
      });
      const res = await submitContributions({
        schema_name: submitSchemaName, namespace_name: submitNamespace, contributions,
      });
      setSubmitResult(res.data);
    } catch (err) {
      setSubmitResult({ error: 'Failed to submit contributions' });
    }
  };

  const handleRequestAccess = async (schemaId: string) => {
    if (!accessNs) { setMessage('Enter your namespace first'); return; }
    try {
      const res = await requestContributionAccess({ schema_id: schemaId, namespace_name: accessNs });
      setMessage(`Access ${res.data.status} for schema`);
    } catch { setMessage('Request failed'); }
  };

  return (
    <div className="page">
      <h1>Enrich In (Contributions)</h1>
      <p>Define schemas, contribute metadata to entities, and browse the contribution marketplace.</p>

      <div className="toggle-group" style={{ marginBottom: '24px' }}>
        <button className={`toggle-btn ${tab === 'browse' ? 'active' : ''}`} onClick={() => setTab('browse')}>Browse Schemas</button>
        <button className={`toggle-btn ${tab === 'define' ? 'active' : ''}`} onClick={() => setTab('define')}>Define Schema</button>
        <button className={`toggle-btn ${tab === 'submit' ? 'active' : ''}`} onClick={() => setTab('submit')}>Submit Data</button>
      </div>

      {tab === 'browse' && (
        <>
          <div className="form-group" style={{ display: 'flex', gap: '8px', marginBottom: '16px' }}>
            <input value={accessNs} onChange={(e) => setAccessNs(e.target.value)} placeholder="Your namespace (for access requests)" style={{ flex: 1 }} />
          </div>
          {message && <div className="info">{message}</div>}
          {loading ? <p>Loading...</p> : (
            <table>
              <thead><tr><th>Schema Name</th><th>Entity Type</th><th>Description</th><th>Fields</th><th>Entities</th><th>Created By</th><th></th><th></th></tr></thead>
              <tbody>
                {schemas.map((s, i) => {
                  const schemaId = s.schema_id as string;
                  const isExpanded = expandedSchema === schemaId;
                  const fields = (s.field_definitions || []) as Record<string, unknown>[];
                  return (
                    <>
                      <tr key={i}>
                        <td><strong>{s.schema_name as string}</strong></td>
                        <td>{s.entity_type as string}</td>
                        <td>{(s.description as string)?.slice(0, 40) || '-'}</td>
                        <td>{fields.length}</td>
                        <td>{s.entity_count as number}</td>
                        <td>{s.created_by as string}</td>
                        <td><button onClick={() => setExpandedSchema(isExpanded ? null : schemaId)}>Info</button></td>
                        <td><button onClick={() => handleRequestAccess(schemaId)}>Request Access</button></td>
                      </tr>
                      {isExpanded && (
                        <tr key={schemaId + '-detail'} className="audit-detail-row">
                          <td colSpan={8}>
                            <div className="audit-detail">
                              <div className="audit-detail-section" style={{ flex: 2 }}>
                                <h4>Description</h4>
                                <p style={{ fontSize: '13px', color: 'var(--text)' }}>{s.description as string || 'No description'}</p>
                              </div>
                              <div className="audit-detail-section" style={{ flex: 3 }}>
                                <h4>Field Definitions</h4>
                                <table>
                                  <thead><tr><th>Name</th><th>Type</th><th>Description</th></tr></thead>
                                  <tbody>
                                    {fields.map((f, fi) => (
                                      <tr key={fi}>
                                        <td><code>{f.name as string}</code></td>
                                        <td>{f.type as string}</td>
                                        <td>{f.description as string || '-'}</td>
                                      </tr>
                                    ))}
                                  </tbody>
                                </table>
                              </div>
                              <div className="audit-detail-section">
                                <h4>Stats</h4>
                                <p style={{ fontSize: '13px' }}>Contributions: {s.contribution_count as number}</p>
                                <p style={{ fontSize: '13px' }}>Unique entities: {s.entity_count as number}</p>
                                <p style={{ fontSize: '13px' }}>Created: {(s.created_at as string)?.slice(0, 10)}</p>
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
        </>
      )}

      {tab === 'define' && (
        <div className="result">
          <h3>Define Contribution Schema</h3>
          <div className="form-group"><label>Schema Name</label><input value={schemaName} onChange={(e) => setSchemaName(e.target.value)} placeholder="e.g., SUSTAINABILITY_SCORES" /></div>
          <div className="form-group"><label>Description</label><input value={schemaDesc} onChange={(e) => setSchemaDesc(e.target.value)} placeholder="What this contribution represents" /></div>
          <div className="form-group">
            <label>Entity Type</label>
            <select value={schemaEntityType} onChange={(e) => setSchemaEntityType(e.target.value)}>
              <option value="PRODUCT">PRODUCT</option>
              <option value="PERSON">PERSON</option>
              <option value="LOCATION">LOCATION</option>
            </select>
          </div>
          <div className="form-group"><label>Namespace (owner)</label><input value={schemaNamespace} onChange={(e) => setSchemaNamespace(e.target.value)} placeholder="e.g., PARTNER_ALPHA" /></div>
          <div className="form-group">
            <label>Field Definitions (one per line: name,type,description)</label>
            <textarea value={fieldsText} onChange={(e) => setFieldsText(e.target.value)} rows={5} placeholder="carbon_footprint,FLOAT,CO2 emissions in kg&#10;recyclable,BOOLEAN,Whether product is recyclable&#10;eco_certification,VARCHAR,Certification body name" />
          </div>
          <button onClick={handleDefineSchema}>Create Schema</button>
          {defineResult && <div className="info" style={{ marginTop: '12px' }}>{JSON.stringify(defineResult)}</div>}
        </div>
      )}

      {tab === 'submit' && (
        <div className="result">
          <h3>Submit Contributions</h3>
          <div className="form-group"><label>Schema Name</label><input value={submitSchemaName} onChange={(e) => setSubmitSchemaName(e.target.value)} placeholder="e.g., SUSTAINABILITY_SCORES" /></div>
          <div className="form-group"><label>Namespace</label><input value={submitNamespace} onChange={(e) => setSubmitNamespace(e.target.value)} placeholder="e.g., PARTNER_ALPHA" /></div>
          <div className="form-group">
            <label>Contributions (one per line: encoded_id,JSON attributes)</label>
            <textarea value={contributionsText} onChange={(e) => setContributionsText(e.target.value)} rows={8} placeholder='abc123...,{"carbon_footprint": 2.5, "recyclable": true}&#10;def456...,{"carbon_footprint": 8.1, "recyclable": false}' />
          </div>
          <button onClick={handleSubmit}>Submit Contributions</button>
          {submitResult && (
            <div className="info" style={{ marginTop: '12px' }}>
              {submitResult.error ? `Error: ${submitResult.error}` : `Contributed: ${submitResult.contributed}, Unmatched: ${submitResult.unmatched}`}
            </div>
          )}
        </div>
      )}

      <div className="demo-box">
        <div className="demo-box-header">Demo</div>
        <div className="demo-buttons">
          <DemoButton label="Define Schema" onClick={async () => { setTab('define'); setSchemaName('SUSTAINABILITY_SCORES_' + Math.random().toString(36).slice(2, 6).toUpperCase()); setSchemaDesc('Environmental sustainability metrics for products'); setSchemaEntityType('PRODUCT'); setSchemaNamespace('PARTNER_ALPHA'); setFieldsText('carbon_footprint,FLOAT,CO2 emissions in kg per unit\nrecyclable,BOOLEAN,Whether packaging is recyclable\neco_certification,VARCHAR,Certification body name'); setDefineResult(null); }} />
          <DemoButton label="Submit 50 Contributions" onClick={async () => { const r = await getRandomDemoEncodingsBatch(50); const d = r.data; setTab('submit'); setSubmitSchemaName(schemas.length > 0 ? schemas[0].schema_name as string : 'SUSTAINABILITY_SCORES'); setSubmitNamespace(d.namespace); const lines = d.encoded_ids.map((id: string) => `${id},{"carbon_footprint": ${(Math.random() * 10).toFixed(1)}, "recyclable": ${Math.random() > 0.5}, "eco_certification": "${['FSC', 'EPA', 'EU_ECOLABEL', 'NONE'][Math.floor(Math.random() * 4)]}"}`); setContributionsText(lines.join('\n')); setSubmitResult(null); }} />
        </div>
      </div>
    </div>
  );
}
