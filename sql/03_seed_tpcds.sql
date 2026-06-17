-- Entity Vault: Seed TPC-DS Product Entities
-- Seeds ~201K product entities from TPC-DS ITEM table (active records only).
-- Prerequisites: Run 01_setup_database.sql first.

USE DATABASE ENTITY_VAULT_DB;

-- =============================================================================
-- STEP 1: Register PRODUCT Entity Type Schema
-- =============================================================================
INSERT INTO CORE.ENTITY_TYPE_SCHEMAS (CLASS_NAME, CLASS_LABEL, CLASS_DESCRIPTION, ATTRIBUTES, RESOLUTION_CONFIG)
SELECT
    'PRODUCT',
    'Product / Retail Item',
    'Consumer retail products sourced from TPC-DS ITEM dimension. Supports brand-level resolution, category enrichment, and cross-partner collaboration.',
    PARSE_JSON('{
        "field_definitions": [
            {"name": "i_item_id",       "type": "VARCHAR", "classification": "IDENTIFIABLE", "description": "Business item identifier"},
            {"name": "i_item_sk",       "type": "NUMBER",  "classification": "INTERNAL",     "description": "Surrogate key from source system"},
            {"name": "i_product_name",  "type": "VARCHAR", "classification": "ENRICHMENT",   "description": "Product display name"},
            {"name": "i_item_desc",     "type": "VARCHAR", "classification": "ENRICHMENT",   "description": "Product description"},
            {"name": "i_brand",         "type": "VARCHAR", "classification": "ENRICHMENT",   "description": "Brand name"},
            {"name": "i_brand_id",      "type": "NUMBER",  "classification": "INTERNAL",     "description": "Brand identifier"},
            {"name": "i_category",      "type": "VARCHAR", "classification": "ENRICHMENT",   "description": "Product category"},
            {"name": "i_category_id",   "type": "NUMBER",  "classification": "INTERNAL",     "description": "Category identifier"},
            {"name": "i_class",         "type": "VARCHAR", "classification": "ENRICHMENT",   "description": "Product class within category"},
            {"name": "i_class_id",      "type": "NUMBER",  "classification": "INTERNAL",     "description": "Class identifier"},
            {"name": "i_manufact",      "type": "VARCHAR", "classification": "ENRICHMENT",   "description": "Manufacturer name"},
            {"name": "i_manufact_id",   "type": "NUMBER",  "classification": "INTERNAL",     "description": "Manufacturer identifier"},
            {"name": "i_current_price", "type": "NUMBER",  "classification": "ENRICHMENT",   "description": "Current retail price"},
            {"name": "i_wholesale_cost","type": "NUMBER",  "classification": "INTERNAL",     "description": "Wholesale cost"},
            {"name": "i_size",          "type": "VARCHAR", "classification": "ENRICHMENT",   "description": "Product size"},
            {"name": "i_color",         "type": "VARCHAR", "classification": "ENRICHMENT",   "description": "Product color"},
            {"name": "i_units",         "type": "VARCHAR", "classification": "ENRICHMENT",   "description": "Unit of measure"},
            {"name": "i_container",     "type": "VARCHAR", "classification": "ENRICHMENT",   "description": "Container type"},
            {"name": "i_formulation",   "type": "VARCHAR", "classification": "INTERNAL",     "description": "Product formulation code"},
            {"name": "i_manager_id",    "type": "NUMBER",  "classification": "INTERNAL",     "description": "Responsible manager ID"}
        ]
    }'),
    PARSE_JSON('{
        "deterministic_keys": ["i_item_id"],
        "fuzzy_fields": ["i_product_name", "i_brand", "i_item_desc"],
        "embedding_model": "snowflake-arctic-embed-l-v2.0",
        "similarity_threshold": 0.78
    }')
WHERE NOT EXISTS (SELECT 1 FROM CORE.ENTITY_TYPE_SCHEMAS WHERE CLASS_NAME = 'PRODUCT');

-- =============================================================================
-- STEP 2: Bulk Insert Entities from TPC-DS ITEM
-- =============================================================================
INSERT INTO CORE.ENTITIES (ENTITY_ID, ENTITY_TYPE, LIFECYCLE_STATE, TRUST_TIER, METADATA, CREATED_AT)
SELECT
    UUID_STRING(),
    'PRODUCT',
    'ACTIVE',
    'AUTHORITATIVE',
    OBJECT_CONSTRUCT(
        'i_item_sk',       I_ITEM_SK,
        'i_item_id',       I_ITEM_ID,
        'i_product_name',  I_PRODUCT_NAME,
        'i_item_desc',     I_ITEM_DESC,
        'i_brand',         I_BRAND,
        'i_brand_id',      I_BRAND_ID,
        'i_category',      I_CATEGORY,
        'i_category_id',   I_CATEGORY_ID,
        'i_class',         I_CLASS,
        'i_class_id',      I_CLASS_ID,
        'i_manufact',      I_MANUFACT,
        'i_manufact_id',   I_MANUFACT_ID,
        'i_current_price', I_CURRENT_PRICE,
        'i_wholesale_cost',I_WHOLESALE_COST,
        'i_size',          I_SIZE,
        'i_color',         I_COLOR,
        'i_units',         I_UNITS,
        'i_container',     I_CONTAINER,
        'i_formulation',   I_FORMULATION,
        'i_manager_id',    I_MANAGER_ID
    ),
    CURRENT_TIMESTAMP()
FROM SFSALESSHARED_SFC_SAMPLES_PROD3_SAMPLE_DATA.TPCDS_SF10TCL.ITEM
WHERE I_REC_END_DATE IS NULL;

-- =============================================================================
-- STEP 3: Create Identifiers (ITEM_ID and ITEM_SK)
-- =============================================================================

-- ITEM_ID identifier (business key)
INSERT INTO CORE.IDENTIFIERS (IDENTIFIER_ID, ENTITY_ID, IDENTIFIER_TYPE, IDENTIFIER_VALUE, NORMALIZED_VALUE_HASH, SOURCE_SYSTEM, CONFIDENCE_SCORE, LINK_TYPE)
SELECT
    UUID_STRING(),
    e.ENTITY_ID,
    'ITEM_ID',
    e.METADATA:i_item_id::VARCHAR,
    SHA2(LOWER(TRIM(e.METADATA:i_item_id::VARCHAR)), 256),
    'TPC-DS',
    1.0,
    'DETERMINISTIC'
FROM CORE.ENTITIES e
WHERE e.ENTITY_TYPE = 'PRODUCT'
  AND NOT EXISTS (
      SELECT 1 FROM CORE.IDENTIFIERS i
      WHERE i.ENTITY_ID = e.ENTITY_ID AND i.IDENTIFIER_TYPE = 'ITEM_ID'
  );

-- ITEM_SK identifier (surrogate key)
INSERT INTO CORE.IDENTIFIERS (IDENTIFIER_ID, ENTITY_ID, IDENTIFIER_TYPE, IDENTIFIER_VALUE, NORMALIZED_VALUE_HASH, SOURCE_SYSTEM, CONFIDENCE_SCORE, LINK_TYPE)
SELECT
    UUID_STRING(),
    e.ENTITY_ID,
    'ITEM_SK',
    e.METADATA:i_item_sk::VARCHAR,
    SHA2(e.METADATA:i_item_sk::VARCHAR, 256),
    'TPC-DS',
    1.0,
    'DETERMINISTIC'
FROM CORE.ENTITIES e
WHERE e.ENTITY_TYPE = 'PRODUCT'
  AND NOT EXISTS (
      SELECT 1 FROM CORE.IDENTIFIERS i
      WHERE i.ENTITY_ID = e.ENTITY_ID AND i.IDENTIFIER_TYPE = 'ITEM_SK'
  );

-- =============================================================================
-- STEP 4: Populate Entity Embeddings
-- NOTE: ~201K records. Recommend running in batches of 50K if timeout occurs.
--       Each batch takes approximately 3-5 minutes depending on warehouse size.
--       Use LIMIT/OFFSET pattern below if needed.
-- =============================================================================

-- Full load (use XL warehouse for best performance):
-- ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'X-LARGE';

INSERT INTO RESOLUTION.ENTITY_EMBEDDINGS (ENTITY_ID, ENTITY_TYPE, SEARCH_TEXT, EMBEDDING)
SELECT
    e.ENTITY_ID,
    e.ENTITY_TYPE,
    CONCAT_WS(' | ',
        COALESCE('product: '  || e.METADATA:i_product_name::VARCHAR, ''),
        COALESCE('brand: '    || e.METADATA:i_brand::VARCHAR, ''),
        COALESCE('category: ' || e.METADATA:i_category::VARCHAR, ''),
        COALESCE('class: '    || e.METADATA:i_class::VARCHAR, ''),
        COALESCE('mfr: '      || e.METADATA:i_manufact::VARCHAR, ''),
        COALESCE('color: '    || e.METADATA:i_color::VARCHAR, ''),
        COALESCE('size: '     || e.METADATA:i_size::VARCHAR, ''),
        COALESCE('desc: '     || LEFT(e.METADATA:i_item_desc::VARCHAR, 200), '')
    ) AS search_text,
    SNOWFLAKE.CORTEX.EMBED_TEXT_1024('snowflake-arctic-embed-l-v2.0', search_text)
FROM CORE.ENTITIES e
WHERE e.ENTITY_TYPE = 'PRODUCT'
  AND NOT EXISTS (
      SELECT 1 FROM RESOLUTION.ENTITY_EMBEDDINGS ee WHERE ee.ENTITY_ID = e.ENTITY_ID
  );

-- OPTIONAL: Batch approach (uncomment and run sequentially if full load times out)
/*
-- Batch 1: first 50K
INSERT INTO RESOLUTION.ENTITY_EMBEDDINGS (ENTITY_ID, ENTITY_TYPE, SEARCH_TEXT, EMBEDDING)
WITH ranked AS (
    SELECT e.ENTITY_ID, e.ENTITY_TYPE, e.METADATA,
           ROW_NUMBER() OVER (ORDER BY e.ENTITY_ID) AS rn
    FROM CORE.ENTITIES e
    WHERE e.ENTITY_TYPE = 'PRODUCT'
      AND NOT EXISTS (SELECT 1 FROM RESOLUTION.ENTITY_EMBEDDINGS ee WHERE ee.ENTITY_ID = e.ENTITY_ID)
)
SELECT
    ENTITY_ID, ENTITY_TYPE,
    CONCAT_WS(' | ',
        COALESCE('product: '  || METADATA:i_product_name::VARCHAR, ''),
        COALESCE('brand: '    || METADATA:i_brand::VARCHAR, ''),
        COALESCE('category: ' || METADATA:i_category::VARCHAR, ''),
        COALESCE('class: '    || METADATA:i_class::VARCHAR, ''),
        COALESCE('mfr: '      || METADATA:i_manufact::VARCHAR, ''),
        COALESCE('color: '    || METADATA:i_color::VARCHAR, ''),
        COALESCE('size: '     || METADATA:i_size::VARCHAR, ''),
        COALESCE('desc: '     || LEFT(METADATA:i_item_desc::VARCHAR, 200), '')
    ) AS search_text,
    SNOWFLAKE.CORTEX.EMBED_TEXT_1024('snowflake-arctic-embed-l-v2.0', search_text)
FROM ranked WHERE rn <= 50000;

-- Batch 2: 50K-100K (run after batch 1 completes)
-- Re-run same query; the NOT EXISTS filter auto-skips already-embedded rows.

-- Batch 3: 100K-150K
-- Batch 4: 150K-201K
-- Each re-run of the full INSERT with NOT EXISTS will process the next unembedded batch.
*/

-- =============================================================================
-- STEP 5: Create Search Base Table (for Cortex Search Service)
-- =============================================================================
CREATE OR REPLACE TABLE RESOLUTION.ENTITIES_SEARCH_BASE (
    ENTITY_ID VARCHAR(36) NOT NULL,
    ENTITY_TYPE VARCHAR(50) NOT NULL,
    SEARCH_TEXT VARCHAR(16000),
    UPDATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Base table for Cortex Search Service - tracks entity search text with change tracking';

INSERT INTO RESOLUTION.ENTITIES_SEARCH_BASE (ENTITY_ID, ENTITY_TYPE, SEARCH_TEXT, UPDATED_AT)
SELECT
    ENTITY_ID,
    ENTITY_TYPE,
    SEARCH_TEXT,
    EMBEDDED_AT
FROM RESOLUTION.ENTITY_EMBEDDINGS;

-- =============================================================================
-- STEP 6: Create Cortex Search Service
-- =============================================================================
CREATE OR REPLACE CORTEX SEARCH SERVICE RESOLUTION.ENTITY_SEARCH_SVC
    ON SEARCH_TEXT
    ATTRIBUTES ENTITY_TYPE
    WAREHOUSE = COMPUTE_WH
    TARGET_LAG = '1 hour'
    AS (
        SELECT
            ENTITY_ID,
            ENTITY_TYPE,
            SEARCH_TEXT
        FROM RESOLUTION.ENTITIES_SEARCH_BASE
    );

-- =============================================================================
-- VERIFICATION
-- =============================================================================
SELECT 'ENTITY_TYPE_SCHEMAS' AS table_name, COUNT(*) AS row_count FROM CORE.ENTITY_TYPE_SCHEMAS WHERE CLASS_NAME = 'PRODUCT'
UNION ALL
SELECT 'ENTITIES (PRODUCT)', COUNT(*) FROM CORE.ENTITIES WHERE ENTITY_TYPE = 'PRODUCT'
UNION ALL
SELECT 'IDENTIFIERS', COUNT(*) FROM CORE.IDENTIFIERS WHERE SOURCE_SYSTEM = 'TPC-DS'
UNION ALL
SELECT 'ENTITY_EMBEDDINGS', COUNT(*) FROM RESOLUTION.ENTITY_EMBEDDINGS WHERE ENTITY_TYPE = 'PRODUCT'
UNION ALL
SELECT 'ENTITIES_SEARCH_BASE', COUNT(*) FROM RESOLUTION.ENTITIES_SEARCH_BASE;
