import axios from 'axios';

const api = axios.create({
  baseURL: 'http://localhost:8000/api',
  headers: { 'Content-Type': 'application/json' },
});

export const resolveEntity = (data: {
  entity_type: string;
  identifiers?: { type: string; value: string }[];
  metadata?: Record<string, unknown>;
  strategy?: string;
}) => api.post('/resolve', data);

export const encodeEntity = (data: { entity_id: string; namespace_name: string }) =>
  api.post('/encode', data);

export const transcodeEntity = (data: {
  encoded_id: string;
  source_namespace: string;
  target_namespace: string;
}) => api.post('/transcode', data);

export const enrichOut = (data: { encoded_ids: string[]; namespace_name: string }) =>
  api.post('/enrich-out', data);

export const enrichIn = (data: {
  group_name: string;
  group_description: string;
  entity_type: string;
  category_schema: Record<string, unknown>;
  namespace_name: string;
  members: { encoded_id: string; category_value: string }[];
}) => api.post('/enrich-in', data);

export const listGroups = (entityType?: string) =>
  api.get('/groups', { params: entityType ? { entity_type: entityType } : {} });

export const requestGroupAccess = (data: {
  group_id: string;
  namespace_name: string;
  access_level?: string;
}) => api.post('/groups/request-access', data);

export const listEntities = (params?: {
  entity_type?: string;
  search?: string;
  limit?: number;
  offset?: number;
}) => api.get('/entities', { params });

export const getEntity = (entityId: string) => api.get(`/entities/${entityId}`);

export const listNamespaces = () => api.get('/namespaces');

export const getNamespaceDetail = (namespaceName: string, params?: { limit?: number; offset?: number }) =>
  api.get(`/namespaces/${namespaceName}/detail`, { params });

export const createNamespace = (data: {
  namespace_name: string;
  description?: string;
  owner_org?: string;
  clearance_level?: string;
}) => api.post('/namespaces', data);

export const getAuditLog = (params?: {
  operation?: string;
  entity_id?: string;
  namespace?: string;
  limit?: number;
  offset?: number;
}) => api.get('/audit', { params });

export const getRandomDemoEntity = () => api.get('/demo/random-entity');
export const getRandomDemoEncoding = () => api.get('/demo/random-encoding');
export const getRandomDemoEncodingsBatch = (count = 100) => api.get('/demo/random-encodings-batch', { params: { count } });

// Contributions
export const createContributionSchema = (data: {
  schema_name: string;
  description?: string;
  entity_type: string;
  namespace_name: string;
  field_definitions: { name: string; type: string; description?: string }[];
}) => api.post('/contributions/schemas', data);

export const listContributionSchemas = (entityType?: string) =>
  api.get('/contributions/schemas', { params: entityType ? { entity_type: entityType } : {} });

export const submitContributions = (data: {
  schema_name: string;
  namespace_name: string;
  contributions: { encoded_id: string; attributes: Record<string, unknown> }[];
}) => api.post('/contributions/submit', data);

export const requestContributionAccess = (data: { schema_id: string; namespace_name: string }) =>
  api.post('/contributions/request-access', data);

export default api;
