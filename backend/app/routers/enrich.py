from fastapi import APIRouter, HTTPException
from app.models.requests import EnrichOutRequest, EnrichInRequest, GroupAccessRequest
from app.snowflake_client import call_procedure

router = APIRouter(prefix="/api", tags=["enrichment"])


@router.post("/enrich-out")
def enrich_out(req: EnrichOutRequest):
    result = call_procedure(
        "ENTITY_VAULT_DB.ENRICHMENT.SP_ENRICH_OUT",
        req.encoded_ids,
        req.namespace_name,
    )
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return result


@router.post("/enrich-in")
def enrich_in(req: EnrichInRequest):
    result = call_procedure(
        "ENTITY_VAULT_DB.ENRICHMENT.SP_ENRICH_IN",
        req.group_name,
        req.group_description,
        req.entity_type,
        req.category_schema,
        req.namespace_name,
        req.members,
    )
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return result


@router.get("/groups")
def list_groups(entity_type: str = None):
    result = call_procedure(
        "ENTITY_VAULT_DB.ENRICHMENT.SP_LIST_GROUPS",
        entity_type,
    )
    return result


@router.post("/groups/request-access")
def request_group_access(req: GroupAccessRequest):
    result = call_procedure(
        "ENTITY_VAULT_DB.ENRICHMENT.SP_REQUEST_GROUP_ACCESS",
        req.group_id,
        req.namespace_name,
        req.access_level,
    )
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return result
