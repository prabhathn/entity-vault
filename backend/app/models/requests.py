from pydantic import BaseModel
from typing import Optional


class ResolveRequest(BaseModel):
    entity_type: str
    identifiers: Optional[list[dict]] = None
    metadata: Optional[dict] = None
    strategy: str = "AUTO"


class EncodeRequest(BaseModel):
    entity_id: str
    namespace_name: str


class TranscodeRequest(BaseModel):
    encoded_id: str
    source_namespace: str
    target_namespace: str


class EnrichOutRequest(BaseModel):
    encoded_ids: list[str]
    namespace_name: str


class EnrichInRequest(BaseModel):
    group_name: str
    group_description: str
    entity_type: str
    category_schema: dict
    namespace_name: str
    members: list[dict]


class NamespaceCreateRequest(BaseModel):
    namespace_name: str
    description: Optional[str] = None
    owner_org: Optional[str] = None
    clearance_level: str = "ENRICHMENT"


class GroupAccessRequest(BaseModel):
    group_id: str
    namespace_name: str
    access_level: str = "READ"
