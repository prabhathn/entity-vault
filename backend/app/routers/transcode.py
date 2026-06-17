from fastapi import APIRouter, HTTPException
from app.models.requests import TranscodeRequest
from app.snowflake_client import call_procedure

router = APIRouter(prefix="/api", tags=["transcoding"])


@router.post("/transcode")
def transcode_entity(req: TranscodeRequest):
    result = call_procedure(
        "ENTITY_VAULT_DB.ENCODING.SP_TRANSCODE",
        req.encoded_id,
        req.source_namespace,
        req.target_namespace,
    )
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return result
