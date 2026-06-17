from fastapi import APIRouter, HTTPException
from app.models.requests import EncodeRequest
from app.snowflake_client import call_procedure

router = APIRouter(prefix="/api", tags=["encoding"])


@router.post("/encode")
def encode_entity(req: EncodeRequest):
    result = call_procedure(
        "ENTITY_VAULT_DB.ENCODING.SP_ENCODE",
        req.entity_id,
        req.namespace_name,
    )
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return result
