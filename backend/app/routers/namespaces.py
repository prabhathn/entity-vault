import json
from fastapi import APIRouter, HTTPException
from app.models.requests import NamespaceCreateRequest
from app.snowflake_client import execute_query, get_cursor

router = APIRouter(prefix="/api", tags=["namespaces"])


@router.get("/namespaces")
def list_namespaces():
    sql = """
        SELECT n.NAMESPACE_ID, n.NAMESPACE_NAME, n.DESCRIPTION, n.OWNER_ORG,
               n.CLEARANCE_LEVEL, n.STATUS, n.CREATED_AT,
               (SELECT COUNT(*) FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS ne WHERE ne.NAMESPACE_ID = n.NAMESPACE_ID) AS encoding_count
        FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES n
        ORDER BY n.CREATED_AT DESC
    """
    return execute_query(sql)


@router.post("/namespaces")
def create_namespace(req: NamespaceCreateRequest):
    with get_cursor() as cur:
        # Create namespace
        cur.execute(
            """INSERT INTO ENTITY_VAULT_DB.ENCODING.NAMESPACES 
               (NAMESPACE_NAME, DESCRIPTION, OWNER_ORG, CLEARANCE_LEVEL) 
               SELECT %s, %s, %s, %s""",
            (req.namespace_name, req.description, req.owner_org, req.clearance_level),
        )

        # Get the namespace ID
        cur.execute(
            "SELECT NAMESPACE_ID FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES WHERE NAMESPACE_NAME = %s",
            (req.namespace_name,),
        )
        ns_id = cur.fetchone()[0]

        # Generate and store HMAC key
        cur.execute(
            """INSERT INTO ENTITY_VAULT_DB.ENCODING.NAMESPACE_KEY_VERSIONS 
               (NAMESPACE_ID, VERSION_NUMBER, HMAC_SECRET_ENCRYPTED, IS_ACTIVE)
               SELECT %s, 1, SHA2(%s || '_secret_v1_' || UUID_STRING(), 256), TRUE""",
            (ns_id, req.namespace_name),
        )

    return {"namespace_id": ns_id, "namespace_name": req.namespace_name, "status": "created"}


@router.get("/namespaces/{namespace_name}/detail")
def get_namespace_detail(namespace_name: str, limit: int = 50, offset: int = 0):
    # Get namespace info
    ns_rows = execute_query(
        "SELECT NAMESPACE_ID, NAMESPACE_NAME, CLEARANCE_LEVEL, STATUS FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES WHERE NAMESPACE_NAME = %s",
        (namespace_name,),
    )
    if not ns_rows:
        return {"error": "Namespace not found"}

    ns = ns_rows[0]
    ns_id = ns["namespace_id"]

    # Stats: total encodings
    stats = execute_query(
        "SELECT COUNT(*) AS total_encodings FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS WHERE NAMESPACE_ID = %s",
        (ns_id,),
    )

    # Stats: resolution tier breakdown from audit log
    tier_breakdown = execute_query(
        """SELECT RESOLUTION_TIER, COUNT(*) AS cnt,
                  ROUND(AVG(CONFIDENCE_SCORE), 3) AS avg_confidence
           FROM ENTITY_VAULT_DB.AUDIT.AUDIT_LOG
           WHERE OPERATION = 'RESOLVE' AND ENTITY_ID IN (
               SELECT ENTITY_ID FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS WHERE NAMESPACE_ID = %s
           )
           AND RESOLUTION_TIER IS NOT NULL
           GROUP BY RESOLUTION_TIER
           ORDER BY cnt DESC""",
        (ns_id,),
    )

    # Encodings list (paginated)
    encodings = execute_query(
        """SELECT ne.ENCODED_ID, ne.ENTITY_ID, TO_VARCHAR(ne.CREATED_AT, 'YYYY-MM-DD HH24:MI') AS CREATED_AT
           FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS ne
           WHERE ne.NAMESPACE_ID = %s
           ORDER BY ne.CREATED_AT DESC
           LIMIT %s OFFSET %s""",
        (ns_id, limit, offset),
    )

    return {
        "namespace": ns,
        "stats": {
            "total_encodings": stats[0]["total_encodings"] if stats else 0,
            "tier_breakdown": tier_breakdown,
        },
        "encodings": encodings,
    }
