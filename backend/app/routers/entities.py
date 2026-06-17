from fastapi import APIRouter, Query
from app.snowflake_client import execute_query

router = APIRouter(prefix="/api", tags=["entities"])


@router.get("/entities")
def list_entities(
    entity_type: str = None,
    search: str = None,
    limit: int = Query(default=50, le=200),
    offset: int = 0,
):
    conditions = ["e.LIFECYCLE_STATE = 'ACTIVE'"]
    params = []

    if entity_type:
        conditions.append("e.ENTITY_TYPE = %s")
        params.append(entity_type)

    if search:
        conditions.append("e.METADATA::VARCHAR ILIKE %s")
        params.append(f"%{search}%")

    where_clause = " AND ".join(conditions)

    count_sql = f"SELECT COUNT(*) AS total FROM ENTITY_VAULT_DB.CORE.ENTITIES e WHERE {where_clause}"
    count_result = execute_query(count_sql, tuple(params))
    total = count_result[0]["total"] if count_result else 0

    sql = f"""
        SELECT e.ENTITY_ID, e.ENTITY_TYPE, e.LIFECYCLE_STATE, e.METADATA,
               TO_VARCHAR(e.CREATED_AT, 'YYYY-MM-DD') AS CREATED_AT, e.TRUST_TIER
        FROM ENTITY_VAULT_DB.CORE.ENTITIES e
        WHERE {where_clause}
        ORDER BY e.CREATED_AT DESC
        LIMIT {limit} OFFSET {offset}
    """
    rows = execute_query(sql, tuple(params))
    return {"total": total, "rows": rows}


@router.get("/entities/{entity_id}")
def get_entity(entity_id: str):
    sql = """
        SELECT e.ENTITY_ID, e.ENTITY_TYPE, e.LIFECYCLE_STATE, e.TRUST_TIER,
               e.METADATA, e.CREATED_AT, e.UPDATED_AT
        FROM ENTITY_VAULT_DB.CORE.ENTITIES e
        WHERE e.ENTITY_ID = %s
    """
    entities = execute_query(sql, (entity_id,))
    if not entities:
        return {"error": "Entity not found"}

    entity = entities[0]

    identifiers_sql = """
        SELECT IDENTIFIER_ID, IDENTIFIER_TYPE, IDENTIFIER_VALUE,
               CONFIDENCE_SCORE, LINK_TYPE, FIRST_SEEN_AT
        FROM ENTITY_VAULT_DB.CORE.IDENTIFIERS
        WHERE ENTITY_ID = %s
        ORDER BY CONFIDENCE_SCORE DESC
    """
    entity["identifiers"] = execute_query(identifiers_sql, (entity_id,))

    encodings_sql = """
        SELECT ne.ENCODED_ID, n.NAMESPACE_NAME, ne.CREATED_AT
        FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS ne
        JOIN ENTITY_VAULT_DB.ENCODING.NAMESPACES n ON ne.NAMESPACE_ID = n.NAMESPACE_ID
        WHERE ne.ENTITY_ID = %s
    """
    entity["encodings"] = execute_query(encodings_sql, (entity_id,))

    groups_sql = """
        SELECT g.GROUP_NAME, gm.CATEGORY_VALUE, gm.ASSIGNED_AT
        FROM ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUP_MEMBERS gm
        JOIN ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUPS g ON gm.GROUP_ID = g.GROUP_ID
        WHERE gm.ENTITY_ID = %s
    """
    entity["groups"] = execute_query(groups_sql, (entity_id,))

    return entity
