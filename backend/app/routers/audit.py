from fastapi import APIRouter, Query
from app.snowflake_client import execute_query

router = APIRouter(prefix="/api", tags=["audit"])


@router.get("/audit")
def get_audit_log(
    operation: str = None,
    entity_id: str = None,
    namespace: str = None,
    limit: int = Query(default=50, le=200),
    offset: int = 0,
):
    conditions = []
    params = []

    if operation:
        conditions.append("a.OPERATION = %s")
        params.append(operation)

    if entity_id:
        conditions.append("a.ENTITY_ID = %s")
        params.append(entity_id)

    if namespace:
        conditions.append("a.NAMESPACE_ID IN (SELECT NAMESPACE_ID FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES WHERE NAMESPACE_NAME = %s)")
        params.append(namespace)

    where_clause = " WHERE " + " AND ".join(conditions) if conditions else ""

    sql = f"""
        SELECT a.AUDIT_ID, a.OPERATION, a.ENTITY_ID, a.NAMESPACE_ID, 
               a.TARGET_NAMESPACE_ID, a.GROUP_ID, a.RESOLUTION_TIER,
               a.CONFIDENCE_SCORE, a.POLICY_RESULT, a.PERFORMED_BY,
               TO_VARCHAR(a.PERFORMED_AT, 'YYYY-MM-DD HH24:MI:SS') AS PERFORMED_AT,
               a.INPUT_DATA, a.OUTPUT_DATA, a.ALTERNATIVES
        FROM ENTITY_VAULT_DB.AUDIT.AUDIT_LOG a
        {where_clause}
        ORDER BY a.PERFORMED_AT DESC
        LIMIT {limit} OFFSET {offset}
    """
    return execute_query(sql, tuple(params))
