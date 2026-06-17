from fastapi import APIRouter, HTTPException
from app.models.requests import ResolveRequest
from app.snowflake_client import call_procedure

router = APIRouter(prefix="/api", tags=["resolution"])


@router.post("/resolve")
def resolve_entity(req: ResolveRequest):
    result = call_procedure(
        "ENTITY_VAULT_DB.RESOLUTION.SP_RESOLVE",
        req.entity_type,
        req.identifiers,
        req.metadata,
        req.strategy,
    )
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return result
