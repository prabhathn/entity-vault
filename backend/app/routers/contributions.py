from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from app.snowflake_client import call_procedure, execute_query

router = APIRouter(prefix="/api/contributions", tags=["contributions"])


class CreateSchemaRequest(BaseModel):
    schema_name: str
    description: Optional[str] = None
    entity_type: str
    namespace_name: str
    field_definitions: list[dict]


class ContributeRequest(BaseModel):
    schema_name: str
    namespace_name: str
    contributions: list[dict]  # [{encoded_id, attributes}]


class ContributionAccessRequest(BaseModel):
    schema_id: str
    namespace_name: str


@router.post("/schemas")
def create_contribution_schema(req: CreateSchemaRequest):
    result = call_procedure(
        "ENTITY_VAULT_DB.ENRICHMENT.SP_CREATE_CONTRIBUTION_SCHEMA",
        req.schema_name,
        req.description,
        req.entity_type,
        req.namespace_name,
        req.field_definitions,
    )
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return result


@router.get("/schemas")
def list_contribution_schemas(entity_type: str = None):
    result = call_procedure(
        "ENTITY_VAULT_DB.ENRICHMENT.SP_LIST_CONTRIBUTION_SCHEMAS",
        entity_type,
    )
    return result


@router.post("/submit")
def submit_contributions(req: ContributeRequest):
    result = call_procedure(
        "ENTITY_VAULT_DB.ENRICHMENT.SP_CONTRIBUTE",
        req.schema_name,
        req.namespace_name,
        req.contributions,
    )
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return result


@router.post("/request-access")
def request_contribution_access(req: ContributionAccessRequest):
    result = call_procedure(
        "ENTITY_VAULT_DB.ENRICHMENT.SP_REQUEST_CONTRIBUTION_ACCESS",
        req.schema_id,
        req.namespace_name,
    )
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return result


@router.get("/schemas/{schema_name}/data")
def get_contribution_data(schema_name: str, namespace_name: str, limit: int = 50):
    """View contributions for a schema (if authorized)."""
    rows = execute_query("""
        SELECT ec.ENTITY_ID, ec.ATTRIBUTES, TO_VARCHAR(ec.CONTRIBUTED_AT, 'YYYY-MM-DD HH24:MI') AS CONTRIBUTED_AT,
               cn.NAMESPACE_NAME AS CONTRIBUTED_BY
        FROM ENTITY_VAULT_DB.ENRICHMENT.ENTITY_CONTRIBUTIONS ec
        JOIN ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_SCHEMAS cs ON ec.SCHEMA_ID = cs.SCHEMA_ID
        JOIN ENTITY_VAULT_DB.ENCODING.NAMESPACES cn ON ec.NAMESPACE_ID = cn.NAMESPACE_ID
        WHERE cs.SCHEMA_NAME = %s
          AND (cs.NAMESPACE_ID = (SELECT NAMESPACE_ID FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES WHERE NAMESPACE_NAME = %s)
               OR EXISTS (SELECT 1 FROM ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_ACCESS_GRANTS cag
                          WHERE cag.SCHEMA_ID = cs.SCHEMA_ID
                            AND cag.NAMESPACE_ID = (SELECT NAMESPACE_ID FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES WHERE NAMESPACE_NAME = %s)
                            AND cag.STATUS = 'ACTIVE'))
        QUALIFY ROW_NUMBER() OVER (PARTITION BY ec.ENTITY_ID ORDER BY ec.CONTRIBUTED_AT DESC) = 1
        ORDER BY ec.CONTRIBUTED_AT DESC
        LIMIT %s
    """, (schema_name, namespace_name, namespace_name, limit))
    return rows
