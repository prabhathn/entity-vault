import json
import random
from fastapi import APIRouter
from app.snowflake_client import execute_query

router = APIRouter(prefix="/api", tags=["demo"])


@router.get("/demo/random-entity")
def get_random_demo_entity():
    """Return a random entity with its metadata for demo purposes."""
    rows = execute_query("""
        SELECT e.ENTITY_ID, e.METADATA, e.ENTITY_TYPE
        FROM ENTITY_VAULT_DB.CORE.ENTITIES e
        WHERE e.ENTITY_TYPE = 'PRODUCT' AND e.LIFECYCLE_STATE = 'ACTIVE'
        ORDER BY RANDOM()
        LIMIT 1
    """)
    if not rows:
        return {"error": "No entities found"}

    entity = rows[0]
    metadata = json.loads(entity["metadata"]) if isinstance(entity["metadata"], str) else entity["metadata"]

    # Build noisy metadata for fuzzy demo (drop 1-2 fields, keep 3-4 descriptors)
    descriptor_fields = ["i_brand", "i_category", "i_class", "i_manufact", "i_product_name", "i_color", "i_size"]
    available = [(k, v) for k, v in metadata.items() if k in descriptor_fields and v and v != "N/A"]
    random.shuffle(available)
    fuzzy_metadata = dict(available[:random.randint(2, min(4, len(available)))])

    # Build mixed metadata (include an identifier field + some descriptors)
    mixed_metadata = {}
    if metadata.get("i_item_id"):
        mixed_metadata["i_item_id"] = metadata["i_item_id"]
    for k, v in available[:2]:
        mixed_metadata[k] = v

    return {
        "entity_id": entity["entity_id"],
        "entity_type": entity["entity_type"],
        "exact_match": {
            "identifier_type": "ITEM_ID",
            "identifier_value": metadata.get("i_item_id", ""),
        },
        "fuzzy_match": {
            "metadata": fuzzy_metadata,
        },
        "mixed_match": {
            "metadata": mixed_metadata,
        },
    }


@router.get("/demo/random-encoding")
def get_random_demo_encoding():
    """Return a random encoded entity for transcode/enrich demos."""
    rows = execute_query("""
        SELECT ne.ENCODED_ID, ne.ENTITY_ID, n.NAMESPACE_NAME
        FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS ne
        JOIN ENTITY_VAULT_DB.ENCODING.NAMESPACES n ON ne.NAMESPACE_ID = n.NAMESPACE_ID
        ORDER BY RANDOM()
        LIMIT 1
    """)
    if not rows:
        return {"error": "No encodings found"}

    enc = rows[0]

    # Find a valid target namespace for transcoding
    targets = execute_query("""
        SELECT n.NAMESPACE_NAME
        FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES n
        WHERE n.NAMESPACE_NAME != %s AND n.STATUS = 'ACTIVE'
        LIMIT 3
    """, (enc["namespace_name"],))

    return {
        "encoded_id": enc["encoded_id"],
        "entity_id": enc["entity_id"],
        "source_namespace": enc["namespace_name"],
        "target_namespaces": [t["namespace_name"] for t in targets],
    }


@router.get("/demo/random-encodings-batch")
def get_random_demo_encodings_batch(count: int = 100):
    """Return multiple random encoded IDs from a single namespace for batch demo scenarios."""
    # Pick a random namespace that has encodings
    ns_rows = execute_query("""
        SELECT n.NAMESPACE_NAME, n.NAMESPACE_ID
        FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES n
        WHERE n.STATUS = 'ACTIVE'
          AND EXISTS (SELECT 1 FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS ne WHERE ne.NAMESPACE_ID = n.NAMESPACE_ID)
        ORDER BY RANDOM()
        LIMIT 1
    """)
    if not ns_rows:
        return {"error": "No encodings found", "encoded_ids": [], "namespace": ""}

    namespace = ns_rows[0]["namespace_name"]
    ns_id = ns_rows[0]["namespace_id"]

    rows = execute_query("""
        SELECT ne.ENCODED_ID
        FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS ne
        WHERE ne.NAMESPACE_ID = %s
        ORDER BY RANDOM()
        LIMIT %s
    """, (ns_id, count))

    ids = [r["encoded_id"] for r in rows]

    return {
        "encoded_ids": ids,
        "namespace": namespace,
        "count": len(ids),
    }
