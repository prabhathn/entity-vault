-- Entity Vault: Seed Demo Namespaces, Encodings, Policies, and Contributions
-- Creates partner namespaces, encodes entities, sets up transcode policies,
-- and seeds contribution data for demonstration purposes.
-- Prerequisites: Run 01_setup_database.sql and 03_seed_tpcds.sql first.

USE DATABASE ENTITY_VAULT_DB;

-- =============================================================================
-- STEP 1: Create Demo Namespaces
-- =============================================================================

-- PARTNER_ALPHA: Sustainability data provider (ENRICHMENT clearance)
INSERT INTO ENCODING.NAMESPACES (NAMESPACE_NAME, DESCRIPTION, OWNER_ORG, CLEARANCE_LEVEL, STATUS)
SELECT 'PARTNER_ALPHA', 'Sustainability & ESG data provider', 'GreenMetrics Corp', 'ENRICHMENT', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM ENCODING.NAMESPACES WHERE NAMESPACE_NAME = 'PARTNER_ALPHA');

-- PARTNER_BETA: Price comparison provider (IDENTIFIABLE clearance)
INSERT INTO ENCODING.NAMESPACES (NAMESPACE_NAME, DESCRIPTION, OWNER_ORG, CLEARANCE_LEVEL, STATUS)
SELECT 'PARTNER_BETA', 'Competitive pricing intelligence', 'PriceWatch Analytics', 'IDENTIFIABLE', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM ENCODING.NAMESPACES WHERE NAMESPACE_NAME = 'PARTNER_BETA');

-- INTERNAL_OPS: Internal operations team (INTERNAL clearance - full access)
INSERT INTO ENCODING.NAMESPACES (NAMESPACE_NAME, DESCRIPTION, OWNER_ORG, CLEARANCE_LEVEL, STATUS)
SELECT 'INTERNAL_OPS', 'Internal operations and data engineering', 'Entity Vault Platform', 'INTERNAL', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM ENCODING.NAMESPACES WHERE NAMESPACE_NAME = 'INTERNAL_OPS');

-- =============================================================================
-- STEP 2: Generate HMAC Keys for Each Namespace
-- =============================================================================

-- PARTNER_ALPHA key
INSERT INTO ENCODING.NAMESPACE_KEY_VERSIONS (NAMESPACE_ID, VERSION_NUMBER, HMAC_SECRET_ENCRYPTED, IS_ACTIVE)
SELECT
    n.NAMESPACE_ID,
    1,
    SHA2(n.NAMESPACE_NAME || '_hmac_secret_v1_' || UUID_STRING(), 256),
    TRUE
FROM ENCODING.NAMESPACES n
WHERE n.NAMESPACE_NAME = 'PARTNER_ALPHA'
  AND NOT EXISTS (
      SELECT 1 FROM ENCODING.NAMESPACE_KEY_VERSIONS k
      WHERE k.NAMESPACE_ID = n.NAMESPACE_ID AND k.IS_ACTIVE = TRUE
  );

-- PARTNER_BETA key
INSERT INTO ENCODING.NAMESPACE_KEY_VERSIONS (NAMESPACE_ID, VERSION_NUMBER, HMAC_SECRET_ENCRYPTED, IS_ACTIVE)
SELECT
    n.NAMESPACE_ID,
    1,
    SHA2(n.NAMESPACE_NAME || '_hmac_secret_v1_' || UUID_STRING(), 256),
    TRUE
FROM ENCODING.NAMESPACES n
WHERE n.NAMESPACE_NAME = 'PARTNER_BETA'
  AND NOT EXISTS (
      SELECT 1 FROM ENCODING.NAMESPACE_KEY_VERSIONS k
      WHERE k.NAMESPACE_ID = n.NAMESPACE_ID AND k.IS_ACTIVE = TRUE
  );

-- INTERNAL_OPS key
INSERT INTO ENCODING.NAMESPACE_KEY_VERSIONS (NAMESPACE_ID, VERSION_NUMBER, HMAC_SECRET_ENCRYPTED, IS_ACTIVE)
SELECT
    n.NAMESPACE_ID,
    1,
    SHA2(n.NAMESPACE_NAME || '_hmac_secret_v1_' || UUID_STRING(), 256),
    TRUE
FROM ENCODING.NAMESPACES n
WHERE n.NAMESPACE_NAME = 'INTERNAL_OPS'
  AND NOT EXISTS (
      SELECT 1 FROM ENCODING.NAMESPACE_KEY_VERSIONS k
      WHERE k.NAMESPACE_ID = n.NAMESPACE_ID AND k.IS_ACTIVE = TRUE
  );

-- =============================================================================
-- STEP 3: Bulk-Encode 500 Random Entities for PARTNER_ALPHA
-- =============================================================================
INSERT INTO ENCODING.NAMESPACE_ENCODINGS (ENCODING_ID, ENTITY_ID, NAMESPACE_ID, ENCODED_ID, KEY_VERSION_ID)
SELECT
    UUID_STRING(),
    e.ENTITY_ID,
    n.NAMESPACE_ID,
    SHA2(e.ENTITY_ID || '::' || k.HMAC_SECRET_ENCRYPTED || '::PARTNER_ALPHA', 256),
    k.KEY_VERSION_ID
FROM (
    SELECT ENTITY_ID
    FROM CORE.ENTITIES
    WHERE ENTITY_TYPE = 'PRODUCT' AND LIFECYCLE_STATE = 'ACTIVE'
    ORDER BY RANDOM()
    LIMIT 500
) e
CROSS JOIN ENCODING.NAMESPACES n
CROSS JOIN ENCODING.NAMESPACE_KEY_VERSIONS k
WHERE n.NAMESPACE_NAME = 'PARTNER_ALPHA'
  AND k.NAMESPACE_ID = n.NAMESPACE_ID
  AND k.IS_ACTIVE = TRUE
  AND NOT EXISTS (
      SELECT 1 FROM ENCODING.NAMESPACE_ENCODINGS ne
      WHERE ne.ENTITY_ID = e.ENTITY_ID AND ne.NAMESPACE_ID = n.NAMESPACE_ID
  );

-- =============================================================================
-- STEP 4: Bulk-Encode 500 Random Entities for PARTNER_BETA
-- =============================================================================
INSERT INTO ENCODING.NAMESPACE_ENCODINGS (ENCODING_ID, ENTITY_ID, NAMESPACE_ID, ENCODED_ID, KEY_VERSION_ID)
SELECT
    UUID_STRING(),
    e.ENTITY_ID,
    n.NAMESPACE_ID,
    SHA2(e.ENTITY_ID || '::' || k.HMAC_SECRET_ENCRYPTED || '::PARTNER_BETA', 256),
    k.KEY_VERSION_ID
FROM (
    SELECT ENTITY_ID
    FROM CORE.ENTITIES
    WHERE ENTITY_TYPE = 'PRODUCT' AND LIFECYCLE_STATE = 'ACTIVE'
    ORDER BY RANDOM()
    LIMIT 500
) e
CROSS JOIN ENCODING.NAMESPACES n
CROSS JOIN ENCODING.NAMESPACE_KEY_VERSIONS k
WHERE n.NAMESPACE_NAME = 'PARTNER_BETA'
  AND k.NAMESPACE_ID = n.NAMESPACE_ID
  AND k.IS_ACTIVE = TRUE
  AND NOT EXISTS (
      SELECT 1 FROM ENCODING.NAMESPACE_ENCODINGS ne
      WHERE ne.ENTITY_ID = e.ENTITY_ID AND ne.NAMESPACE_ID = n.NAMESPACE_ID
  );

-- =============================================================================
-- STEP 5: Create Transcode Policy (ALPHA -> BETA = ALLOW)
-- =============================================================================
INSERT INTO POLICY.TRANSCODE_POLICIES (SOURCE_NAMESPACE_ID, TARGET_NAMESPACE_ID, POLICY_TYPE, STATUS)
SELECT
    src.NAMESPACE_ID,
    tgt.NAMESPACE_ID,
    'ALLOW',
    'ACTIVE'
FROM ENCODING.NAMESPACES src, ENCODING.NAMESPACES tgt
WHERE src.NAMESPACE_NAME = 'PARTNER_ALPHA'
  AND tgt.NAMESPACE_NAME = 'PARTNER_BETA'
  AND NOT EXISTS (
      SELECT 1 FROM POLICY.TRANSCODE_POLICIES tp
      WHERE tp.SOURCE_NAMESPACE_ID = src.NAMESPACE_ID
        AND tp.TARGET_NAMESPACE_ID = tgt.NAMESPACE_ID
  );

-- =============================================================================
-- STEP 6: Create Contribution Schemas
-- =============================================================================

-- SUSTAINABILITY_SCORES: contributed by PARTNER_ALPHA
INSERT INTO ENRICHMENT.CONTRIBUTION_SCHEMAS (SCHEMA_NAME, DESCRIPTION, ENTITY_TYPE, NAMESPACE_ID, FIELD_DEFINITIONS, IS_DISCOVERABLE, STATUS)
SELECT
    'SUSTAINABILITY_SCORES',
    'Environmental sustainability ratings and carbon footprint metrics for products',
    'PRODUCT',
    n.NAMESPACE_ID,
    PARSE_JSON('[
        {"name": "carbon_footprint_kg", "type": "FLOAT",   "description": "CO2 equivalent in kg per unit produced"},
        {"name": "recyclability_pct",   "type": "FLOAT",   "description": "Percentage of materials that are recyclable (0-100)"},
        {"name": "sustainability_grade","type": "VARCHAR", "description": "Letter grade A+ through F"},
        {"name": "water_usage_liters",  "type": "FLOAT",   "description": "Water consumption in liters per unit"},
        {"name": "renewable_energy_pct","type": "FLOAT",   "description": "Percentage of renewable energy used in production"},
        {"name": "assessed_date",       "type": "DATE",    "description": "Date of sustainability assessment"}
    ]'),
    TRUE,
    'ACTIVE'
FROM ENCODING.NAMESPACES n
WHERE n.NAMESPACE_NAME = 'PARTNER_ALPHA'
  AND NOT EXISTS (SELECT 1 FROM ENRICHMENT.CONTRIBUTION_SCHEMAS WHERE SCHEMA_NAME = 'SUSTAINABILITY_SCORES');

-- PRICE_COMPARISON: contributed by PARTNER_BETA
INSERT INTO ENRICHMENT.CONTRIBUTION_SCHEMAS (SCHEMA_NAME, DESCRIPTION, ENTITY_TYPE, NAMESPACE_ID, FIELD_DEFINITIONS, IS_DISCOVERABLE, STATUS)
SELECT
    'PRICE_COMPARISON',
    'Competitive pricing intelligence across multiple retail channels',
    'PRODUCT',
    n.NAMESPACE_ID,
    PARSE_JSON('[
        {"name": "avg_market_price",    "type": "FLOAT",   "description": "Average market price across retailers"},
        {"name": "min_observed_price",  "type": "FLOAT",   "description": "Lowest observed price"},
        {"name": "max_observed_price",  "type": "FLOAT",   "description": "Highest observed price"},
        {"name": "num_retailers",       "type": "INTEGER", "description": "Number of retailers carrying this product"},
        {"name": "price_volatility_pct","type": "FLOAT",   "description": "Price volatility as percentage (std dev / mean * 100)"},
        {"name": "price_trend",         "type": "VARCHAR", "description": "RISING, STABLE, or FALLING"},
        {"name": "observation_date",    "type": "DATE",    "description": "Date of price observation"}
    ]'),
    TRUE,
    'ACTIVE'
FROM ENCODING.NAMESPACES n
WHERE n.NAMESPACE_NAME = 'PARTNER_BETA'
  AND NOT EXISTS (SELECT 1 FROM ENRICHMENT.CONTRIBUTION_SCHEMAS WHERE SCHEMA_NAME = 'PRICE_COMPARISON');

-- =============================================================================
-- STEP 7: Seed 100 Sustainability Score Contributions (from PARTNER_ALPHA)
-- =============================================================================
INSERT INTO ENRICHMENT.ENTITY_CONTRIBUTIONS (CONTRIBUTION_ID, ENTITY_ID, SCHEMA_ID, NAMESPACE_ID, ATTRIBUTES, CONTRIBUTED_AT)
SELECT
    UUID_STRING(),
    ne.ENTITY_ID,
    cs.SCHEMA_ID,
    n.NAMESPACE_ID,
    OBJECT_CONSTRUCT(
        'carbon_footprint_kg', ROUND(UNIFORM(0.5::FLOAT, 25.0::FLOAT, RANDOM()), 2),
        'recyclability_pct',   ROUND(UNIFORM(10.0::FLOAT, 98.0::FLOAT, RANDOM()), 1),
        'sustainability_grade', CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 10 THEN 'A+'
            WHEN UNIFORM(1, 100, RANDOM()) <= 25 THEN 'A'
            WHEN UNIFORM(1, 100, RANDOM()) <= 45 THEN 'B'
            WHEN UNIFORM(1, 100, RANDOM()) <= 70 THEN 'C'
            WHEN UNIFORM(1, 100, RANDOM()) <= 90 THEN 'D'
            ELSE 'F'
        END,
        'water_usage_liters',   ROUND(UNIFORM(2.0::FLOAT, 150.0::FLOAT, RANDOM()), 1),
        'renewable_energy_pct', ROUND(UNIFORM(5.0::FLOAT, 95.0::FLOAT, RANDOM()), 1),
        'assessed_date',        DATEADD(DAY, -UNIFORM(1, 180, RANDOM()), CURRENT_DATE())::VARCHAR
    ),
    DATEADD(MINUTE, -UNIFORM(1, 10000, RANDOM()), CURRENT_TIMESTAMP())
FROM (
    SELECT ne.ENTITY_ID, ROW_NUMBER() OVER (ORDER BY RANDOM()) AS rn
    FROM ENCODING.NAMESPACE_ENCODINGS ne
    JOIN ENCODING.NAMESPACES n ON ne.NAMESPACE_ID = n.NAMESPACE_ID
    WHERE n.NAMESPACE_NAME = 'PARTNER_ALPHA'
) ne
CROSS JOIN ENRICHMENT.CONTRIBUTION_SCHEMAS cs
CROSS JOIN ENCODING.NAMESPACES n
WHERE cs.SCHEMA_NAME = 'SUSTAINABILITY_SCORES'
  AND n.NAMESPACE_NAME = 'PARTNER_ALPHA'
  AND ne.rn <= 100;

-- =============================================================================
-- STEP 8: Seed 100 Price Comparison Contributions (from PARTNER_BETA)
-- =============================================================================
INSERT INTO ENRICHMENT.ENTITY_CONTRIBUTIONS (CONTRIBUTION_ID, ENTITY_ID, SCHEMA_ID, NAMESPACE_ID, ATTRIBUTES, CONTRIBUTED_AT)
SELECT
    UUID_STRING(),
    ne.ENTITY_ID,
    cs.SCHEMA_ID,
    n.NAMESPACE_ID,
    OBJECT_CONSTRUCT(
        'avg_market_price',     ROUND(UNIFORM(5.0::FLOAT, 500.0::FLOAT, RANDOM()), 2),
        'min_observed_price',   ROUND(UNIFORM(3.0::FLOAT, 400.0::FLOAT, RANDOM()), 2),
        'max_observed_price',   ROUND(UNIFORM(50.0::FLOAT, 800.0::FLOAT, RANDOM()), 2),
        'num_retailers',        UNIFORM(2, 25, RANDOM()),
        'price_volatility_pct', ROUND(UNIFORM(1.0::FLOAT, 35.0::FLOAT, RANDOM()), 1),
        'price_trend',          CASE UNIFORM(1, 3, RANDOM())
            WHEN 1 THEN 'RISING'
            WHEN 2 THEN 'STABLE'
            ELSE 'FALLING'
        END,
        'observation_date',     DATEADD(DAY, -UNIFORM(1, 90, RANDOM()), CURRENT_DATE())::VARCHAR
    ),
    DATEADD(MINUTE, -UNIFORM(1, 10000, RANDOM()), CURRENT_TIMESTAMP())
FROM (
    SELECT ne.ENTITY_ID, ROW_NUMBER() OVER (ORDER BY RANDOM()) AS rn
    FROM ENCODING.NAMESPACE_ENCODINGS ne
    JOIN ENCODING.NAMESPACES n ON ne.NAMESPACE_ID = n.NAMESPACE_ID
    WHERE n.NAMESPACE_NAME = 'PARTNER_BETA'
) ne
CROSS JOIN ENRICHMENT.CONTRIBUTION_SCHEMAS cs
CROSS JOIN ENCODING.NAMESPACES n
WHERE cs.SCHEMA_NAME = 'PRICE_COMPARISON'
  AND n.NAMESPACE_NAME = 'PARTNER_BETA'
  AND ne.rn <= 100;

-- =============================================================================
-- STEP 9: Seed Audit Log Entries for Demo Visibility
-- =============================================================================
INSERT INTO AUDIT.AUDIT_LOG (OPERATION, ENTITY_ID, NAMESPACE_ID, INPUT_DATA, OUTPUT_DATA, PERFORMED_BY, PERFORMED_AT)
SELECT
    'ENCODE',
    ne.ENTITY_ID,
    ne.NAMESPACE_ID,
    OBJECT_CONSTRUCT('namespace', n.NAMESPACE_NAME),
    OBJECT_CONSTRUCT('encoded_id', ne.ENCODED_ID),
    'SEED_SCRIPT',
    ne.CREATED_AT
FROM ENCODING.NAMESPACE_ENCODINGS ne
JOIN ENCODING.NAMESPACES n ON ne.NAMESPACE_ID = n.NAMESPACE_ID
WHERE n.NAMESPACE_NAME IN ('PARTNER_ALPHA', 'PARTNER_BETA')
LIMIT 200;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
SELECT '--- DEMO DATA SUMMARY ---' AS SECTION;

SELECT 'NAMESPACES' AS table_name, COUNT(*) AS row_count
FROM ENCODING.NAMESPACES WHERE NAMESPACE_NAME IN ('PARTNER_ALPHA', 'PARTNER_BETA', 'INTERNAL_OPS')
UNION ALL
SELECT 'HMAC_KEYS', COUNT(*)
FROM ENCODING.NAMESPACE_KEY_VERSIONS k
JOIN ENCODING.NAMESPACES n ON k.NAMESPACE_ID = n.NAMESPACE_ID
WHERE n.NAMESPACE_NAME IN ('PARTNER_ALPHA', 'PARTNER_BETA', 'INTERNAL_OPS') AND k.IS_ACTIVE = TRUE
UNION ALL
SELECT 'ENCODINGS (ALPHA)', COUNT(*)
FROM ENCODING.NAMESPACE_ENCODINGS ne
JOIN ENCODING.NAMESPACES n ON ne.NAMESPACE_ID = n.NAMESPACE_ID WHERE n.NAMESPACE_NAME = 'PARTNER_ALPHA'
UNION ALL
SELECT 'ENCODINGS (BETA)', COUNT(*)
FROM ENCODING.NAMESPACE_ENCODINGS ne
JOIN ENCODING.NAMESPACES n ON ne.NAMESPACE_ID = n.NAMESPACE_ID WHERE n.NAMESPACE_NAME = 'PARTNER_BETA'
UNION ALL
SELECT 'TRANSCODE_POLICIES', COUNT(*)
FROM POLICY.TRANSCODE_POLICIES WHERE STATUS = 'ACTIVE'
UNION ALL
SELECT 'CONTRIBUTION_SCHEMAS', COUNT(*)
FROM ENRICHMENT.CONTRIBUTION_SCHEMAS WHERE SCHEMA_NAME IN ('SUSTAINABILITY_SCORES', 'PRICE_COMPARISON')
UNION ALL
SELECT 'CONTRIBUTIONS (SUSTAINABILITY)', COUNT(*)
FROM ENRICHMENT.ENTITY_CONTRIBUTIONS ec
JOIN ENRICHMENT.CONTRIBUTION_SCHEMAS cs ON ec.SCHEMA_ID = cs.SCHEMA_ID WHERE cs.SCHEMA_NAME = 'SUSTAINABILITY_SCORES'
UNION ALL
SELECT 'CONTRIBUTIONS (PRICE)', COUNT(*)
FROM ENRICHMENT.ENTITY_CONTRIBUTIONS ec
JOIN ENRICHMENT.CONTRIBUTION_SCHEMAS cs ON ec.SCHEMA_ID = cs.SCHEMA_ID WHERE cs.SCHEMA_NAME = 'PRICE_COMPARISON'
UNION ALL
SELECT 'AUDIT_LOG (DEMO)', COUNT(*)
FROM AUDIT.AUDIT_LOG WHERE PERFORMED_BY = 'SEED_SCRIPT';
