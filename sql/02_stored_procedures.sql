-- Entity Vault: Stored Procedures and UDFs
-- Run this script AFTER 01_setup_database.sql

-- =============================================================================
-- POLICY UDFs
-- =============================================================================

-- Check if an entity is suppressed for a given operation type
CREATE OR REPLACE FUNCTION ENTITY_VAULT_DB.POLICY.FN_CHECK_SUPPRESSION(
    P_ENTITY_ID VARCHAR,
    P_OPERATION_TYPE VARCHAR
)
RETURNS BOOLEAN
LANGUAGE SQL
AS
$$
    SELECT EXISTS (
        SELECT 1
        FROM ENTITY_VAULT_DB.POLICY.SUPPRESSION_RECORDS
        WHERE ENTITY_ID = P_ENTITY_ID
          AND STATUS = 'ACTIVE'
          AND (SUPPRESSION_TYPE = P_OPERATION_TYPE OR SUPPRESSION_TYPE = 'ALL')
          AND (EXPIRES_AT IS NULL OR EXPIRES_AT > CURRENT_TIMESTAMP())
    )
$$;

-- Check if consent exists for an entity + namespace + operation
CREATE OR REPLACE FUNCTION ENTITY_VAULT_DB.POLICY.FN_CHECK_CONSENT(
    P_ENTITY_ID VARCHAR,
    P_NAMESPACE_ID VARCHAR,
    P_OPERATION_TYPE VARCHAR
)
RETURNS BOOLEAN
LANGUAGE SQL
AS
$$
    SELECT EXISTS (
        SELECT 1
        FROM ENTITY_VAULT_DB.POLICY.CONSENT_RECORDS
        WHERE ENTITY_ID = P_ENTITY_ID
          AND NAMESPACE_ID = P_NAMESPACE_ID
          AND STATUS = 'ACTIVE'
          AND (CONSENT_TYPE = P_OPERATION_TYPE OR CONSENT_TYPE = 'ALL')
          AND (EXPIRES_AT IS NULL OR EXPIRES_AT > CURRENT_TIMESTAMP())
    )
$$;

-- Check transcode policy between two namespaces
-- Returns: 'ALLOW', 'DENY', or 'REQUIRE_CONSENT'
CREATE OR REPLACE FUNCTION ENTITY_VAULT_DB.POLICY.FN_CHECK_TRANSCODE_POLICY(
    P_SOURCE_NS_ID VARCHAR,
    P_TARGET_NS_ID VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
    SELECT COALESCE(
        (SELECT POLICY_TYPE
         FROM ENTITY_VAULT_DB.POLICY.TRANSCODE_POLICIES
         WHERE SOURCE_NAMESPACE_ID = P_SOURCE_NS_ID
           AND TARGET_NAMESPACE_ID = P_TARGET_NS_ID
           AND STATUS = 'ACTIVE'
         ORDER BY CREATED_AT DESC
         LIMIT 1),
        'ALLOW'
    )
$$;

-- Check if a namespace clearance level can access a given field classification
-- Hierarchy: INTERNAL (most restricted) < IDENTIFIABLE < ENRICHMENT (most open)
-- A namespace with clearance X can see fields classified at X or more open levels
CREATE OR REPLACE FUNCTION ENTITY_VAULT_DB.POLICY.FN_CHECK_CLEARANCE(
    P_NAMESPACE_CLEARANCE VARCHAR,
    P_FIELD_CLASSIFICATION VARCHAR
)
RETURNS BOOLEAN
LANGUAGE SQL
AS
$$
    SELECT CASE
        WHEN P_NAMESPACE_CLEARANCE = 'INTERNAL' THEN TRUE
        WHEN P_NAMESPACE_CLEARANCE = 'IDENTIFIABLE' AND P_FIELD_CLASSIFICATION IN ('IDENTIFIABLE', 'ENRICHMENT') THEN TRUE
        WHEN P_NAMESPACE_CLEARANCE = 'ENRICHMENT' AND P_FIELD_CLASSIFICATION = 'ENRICHMENT' THEN TRUE
        ELSE FALSE
    END
$$;

-- =============================================================================
-- AUDIT HELPER
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
    P_OPERATION VARCHAR,
    P_ENTITY_ID VARCHAR,
    P_NAMESPACE_ID VARCHAR,
    P_TARGET_NAMESPACE_ID VARCHAR,
    P_GROUP_ID VARCHAR,
    P_INPUT_DATA VARIANT,
    P_OUTPUT_DATA VARIANT,
    P_RESOLUTION_TIER VARCHAR,
    P_CONFIDENCE_SCORE FLOAT,
    P_ALTERNATIVES VARIANT,
    P_POLICY_RESULT VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
BEGIN
    INSERT INTO ENTITY_VAULT_DB.AUDIT.AUDIT_LOG (
        AUDIT_ID, OPERATION, ENTITY_ID, NAMESPACE_ID, TARGET_NAMESPACE_ID,
        GROUP_ID, INPUT_DATA, OUTPUT_DATA, RESOLUTION_TIER, CONFIDENCE_SCORE,
        ALTERNATIVES, POLICY_RESULT, PERFORMED_BY, PERFORMED_AT
    )
    SELECT
        UUID_STRING(),
        :P_OPERATION,
        :P_ENTITY_ID,
        :P_NAMESPACE_ID,
        :P_TARGET_NAMESPACE_ID,
        :P_GROUP_ID,
        :P_INPUT_DATA,
        :P_OUTPUT_DATA,
        :P_RESOLUTION_TIER,
        :P_CONFIDENCE_SCORE,
        :P_ALTERNATIVES,
        :P_POLICY_RESULT,
        CURRENT_USER(),
        CURRENT_TIMESTAMP();

    RETURN 'OK';
END;

-- =============================================================================
-- RESOLUTION: SP_RESOLVE
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.RESOLUTION.SP_RESOLVE(
    P_ENTITY_TYPE VARCHAR,
    P_IDENTIFIERS VARIANT,
    P_METADATA VARIANT,
    P_STRATEGY VARCHAR DEFAULT 'AUTO'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_entity_id VARCHAR;
    v_confidence FLOAT;
    v_tier VARCHAR;
    v_is_new BOOLEAN DEFAULT FALSE;
    v_alternatives VARIANT DEFAULT PARSE_JSON('[]');
    v_hash VARCHAR;
    v_search_text VARCHAR;
    v_search_results VARIANT;
    v_result VARIANT;
BEGIN
    -- =========================================================================
    -- TIER 1: Exact Hash Lookup
    -- =========================================================================
    IF (P_IDENTIFIERS IS NOT NULL AND ARRAY_SIZE(P_IDENTIFIERS) > 0) THEN
        LET i INTEGER := 0;
        LET id_count INTEGER := ARRAY_SIZE(P_IDENTIFIERS);

        WHILE (i < id_count) DO
            LET id_type VARCHAR := P_IDENTIFIERS[i]:type::VARCHAR;
            LET id_value VARCHAR := P_IDENTIFIERS[i]:value::VARCHAR;

            IF (id_value IS NOT NULL) THEN
                LET computed_hash VARCHAR := SHA2(CONCAT('entity_vault:', LOWER(id_value)));

                SELECT ENTITY_ID INTO :v_entity_id
                FROM ENTITY_VAULT_DB.CORE.IDENTIFIERS
                WHERE NORMALIZED_VALUE_HASH = :computed_hash
                LIMIT 1;

                IF (v_entity_id IS NOT NULL) THEN
                    v_confidence := 1.0;
                    v_tier := 'EXACT_HASH';

                    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
                        'RESOLVE', :v_entity_id, NULL, NULL, NULL,
                        :P_IDENTIFIERS, NULL, :v_tier, :v_confidence, :v_alternatives, NULL
                    );

                    v_result := OBJECT_CONSTRUCT(
                        'entity_id', v_entity_id,
                        'resolution_tier', v_tier,
                        'confidence', v_confidence,
                        'is_new', v_is_new,
                        'alternatives', v_alternatives
                    );
                    RETURN v_result;
                END IF;
            END IF;
            i := i + 1;
        END WHILE;
    END IF;

    -- =========================================================================
    -- TIER 2: Cortex Search (SEARCH_PREVIEW) - Semantic + Lexical hybrid
    -- =========================================================================
    IF (P_METADATA IS NOT NULL AND (P_STRATEGY = 'AUTO' OR P_STRATEGY = 'SEARCH')) THEN
        -- Build search text from metadata
        SELECT ARRAY_TO_STRING(
            ARRAY_AGG(f.KEY || ': ' || f.VALUE::VARCHAR),
            ' | '
        ) INTO :v_search_text
        FROM TABLE(FLATTEN(INPUT => P_METADATA)) f;

        IF (v_search_text IS NOT NULL AND LENGTH(v_search_text) > 0) THEN
            -- Use SEARCH_PREVIEW with string query argument
            LET search_query VARCHAR := v_search_text;
            LET search_results VARIANT;

            SELECT PARSE_JSON(
                SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                    'ENTITY_VAULT_DB.RESOLUTION.ENTITY_SEARCH_SVC',
                    :search_query,
                    '{
                        "columns": ["ENTITY_ID", "ENTITY_TYPE", "SEARCH_TEXT"],
                        "filter": {"@eq": {"ENTITY_TYPE": "' || P_ENTITY_TYPE || '"}},
                        "limit": 5
                    }'
                )
            ) INTO :search_results;

            -- Check if we got results
            IF (search_results:results IS NOT NULL AND ARRAY_SIZE(search_results:results) > 0) THEN
                LET top_score FLOAT := search_results:results[0]:score::FLOAT;

                -- Load resolution config for threshold
                LET search_threshold FLOAT := 0.50;
                SELECT resolution_config:search_threshold::FLOAT INTO :search_threshold
                FROM ENTITY_VAULT_DB.CORE.ENTITY_TYPE_SCHEMAS
                WHERE CLASS_NAME = :P_ENTITY_TYPE;

                IF (top_score >= search_threshold) THEN
                    v_entity_id := search_results:results[0]:ENTITY_ID::VARCHAR;
                    v_confidence := top_score;
                    v_tier := 'CORTEX_SEARCH';

                    -- Collect alternatives (results beyond the top match)
                    LET alt_array VARIANT := PARSE_JSON('[]');
                    LET j INTEGER := 1;
                    LET res_count INTEGER := ARRAY_SIZE(search_results:results);
                    WHILE (j < res_count) DO
                        alt_array := ARRAY_APPEND(alt_array, OBJECT_CONSTRUCT(
                            'entity_id', search_results:results[j]:ENTITY_ID::VARCHAR,
                            'confidence', search_results:results[j]:score::FLOAT,
                            'tier', 'CORTEX_SEARCH'
                        ));
                        j := j + 1;
                    END WHILE;
                    v_alternatives := alt_array;

                    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
                        'RESOLVE', :v_entity_id, NULL, NULL, NULL,
                        :P_METADATA, NULL, :v_tier, :v_confidence, :v_alternatives, NULL
                    );

                    v_result := OBJECT_CONSTRUCT(
                        'entity_id', v_entity_id,
                        'resolution_tier', v_tier,
                        'confidence', v_confidence,
                        'is_new', v_is_new,
                        'alternatives', v_alternatives
                    );
                    RETURN v_result;
                END IF;
            END IF;
        END IF;
    END IF;

    -- =========================================================================
    -- TIER 4: Create New Entity
    -- =========================================================================
    v_entity_id := UUID_STRING();
    v_tier := 'NEW';
    v_confidence := NULL;
    v_is_new := TRUE;

    -- Insert new entity
    INSERT INTO ENTITY_VAULT_DB.CORE.ENTITIES (ENTITY_ID, ENTITY_TYPE, METADATA)
    SELECT :v_entity_id, :P_ENTITY_TYPE, COALESCE(:P_METADATA, PARSE_JSON('{}'));

    -- Insert identifiers if provided
    IF (P_IDENTIFIERS IS NOT NULL AND ARRAY_SIZE(P_IDENTIFIERS) > 0) THEN
        LET k INTEGER := 0;
        LET id_cnt INTEGER := ARRAY_SIZE(P_IDENTIFIERS);
        WHILE (k < id_cnt) DO
            LET id_type_new VARCHAR := P_IDENTIFIERS[k]:type::VARCHAR;
            LET id_value_new VARCHAR := P_IDENTIFIERS[k]:value::VARCHAR;
            IF (id_value_new IS NOT NULL) THEN
                LET new_hash VARCHAR := SHA2(CONCAT('entity_vault:', LOWER(id_value_new)));
                INSERT INTO ENTITY_VAULT_DB.CORE.IDENTIFIERS (
                    IDENTIFIER_ID, ENTITY_ID, IDENTIFIER_TYPE, IDENTIFIER_VALUE,
                    NORMALIZED_VALUE_HASH, SOURCE_SYSTEM, CONFIDENCE_SCORE, LINK_TYPE
                )
                SELECT UUID_STRING(), :v_entity_id, :id_type_new, :id_value_new,
                       :new_hash, 'SP_RESOLVE', 1.0, 'DETERMINISTIC';
            END IF;
            k := k + 1;
        END WHILE;
    END IF;

    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
        'RESOLVE', :v_entity_id, NULL, NULL, NULL,
        COALESCE(:P_IDENTIFIERS, :P_METADATA), NULL, :v_tier, :v_confidence, :v_alternatives, NULL
    );

    v_result := OBJECT_CONSTRUCT(
        'entity_id', v_entity_id,
        'resolution_tier', v_tier,
        'confidence', v_confidence,
        'is_new', v_is_new,
        'alternatives', v_alternatives
    );
    RETURN v_result;
END;

-- =============================================================================
-- ENCODING: SP_ENCODE
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.ENCODING.SP_ENCODE(
    P_ENTITY_ID VARCHAR,
    P_NAMESPACE_NAME VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_namespace_id VARCHAR;
    v_key_version_id VARCHAR;
    v_hmac_secret VARCHAR;
    v_encoded_id VARCHAR;
    v_existing_encoded_id VARCHAR;
    v_is_suppressed BOOLEAN;
    v_result VARIANT;
BEGIN
    -- Lookup namespace
    SELECT NAMESPACE_ID INTO :v_namespace_id
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES
    WHERE NAMESPACE_NAME = :P_NAMESPACE_NAME AND STATUS = 'ACTIVE';

    IF (v_namespace_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Namespace not found or inactive: ' || P_NAMESPACE_NAME);
    END IF;

    -- Check suppression
    v_is_suppressed := ENTITY_VAULT_DB.POLICY.FN_CHECK_SUPPRESSION(P_ENTITY_ID, 'ENCODE');
    IF (v_is_suppressed) THEN
        CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
            'ENCODE', :P_ENTITY_ID, :v_namespace_id, NULL, NULL,
            NULL, NULL, NULL, NULL, NULL, 'SUPPRESSED'
        );
        RETURN OBJECT_CONSTRUCT('error', 'Entity is suppressed for encoding', 'policy_result', 'SUPPRESSED');
    END IF;

    -- Check if encoding already exists (idempotent)
    SELECT ENCODED_ID INTO :v_existing_encoded_id
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS
    WHERE ENTITY_ID = :P_ENTITY_ID AND NAMESPACE_ID = :v_namespace_id;

    IF (v_existing_encoded_id IS NOT NULL) THEN
        v_result := OBJECT_CONSTRUCT(
            'encoded_id', v_existing_encoded_id,
            'namespace', P_NAMESPACE_NAME,
            'cached', TRUE
        );
        RETURN v_result;
    END IF;

    -- Get active HMAC key for namespace
    SELECT KEY_VERSION_ID, HMAC_SECRET_ENCRYPTED
    INTO :v_key_version_id, :v_hmac_secret
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_KEY_VERSIONS
    WHERE NAMESPACE_ID = :v_namespace_id AND IS_ACTIVE = TRUE
    ORDER BY VERSION_NUMBER DESC
    LIMIT 1;

    IF (v_key_version_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'No active HMAC key for namespace: ' || P_NAMESPACE_NAME);
    END IF;

    -- Compute encoded_id: SHA2(secret || ':' || entity_id)
    v_encoded_id := SHA2(CONCAT(v_hmac_secret, ':', P_ENTITY_ID));

    -- Cache in NAMESPACE_ENCODINGS
    INSERT INTO ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS (
        ENCODING_ID, ENTITY_ID, NAMESPACE_ID, ENCODED_ID, KEY_VERSION_ID
    )
    SELECT UUID_STRING(), :P_ENTITY_ID, :v_namespace_id, :v_encoded_id, :v_key_version_id;

    -- Audit
    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
        'ENCODE', :P_ENTITY_ID, :v_namespace_id, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL, 'ALLOW'
    );

    v_result := OBJECT_CONSTRUCT(
        'encoded_id', v_encoded_id,
        'namespace', P_NAMESPACE_NAME,
        'cached', FALSE
    );
    RETURN v_result;
END;

-- =============================================================================
-- ENCODING: SP_TRANSCODE
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.ENCODING.SP_TRANSCODE(
    P_ENCODED_ID VARCHAR,
    P_SOURCE_NAMESPACE VARCHAR,
    P_TARGET_NAMESPACE VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_source_ns_id VARCHAR;
    v_target_ns_id VARCHAR;
    v_entity_id VARCHAR;
    v_policy_result VARCHAR;
    v_is_suppressed BOOLEAN;
    v_has_consent BOOLEAN;
    v_target_encoded_id VARCHAR;
    v_target_key_version_id VARCHAR;
    v_target_hmac_secret VARCHAR;
    v_existing_target_encoded VARCHAR;
    v_result VARIANT;
BEGIN
    -- Lookup source namespace
    SELECT NAMESPACE_ID INTO :v_source_ns_id
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES
    WHERE NAMESPACE_NAME = :P_SOURCE_NAMESPACE AND STATUS = 'ACTIVE';

    IF (v_source_ns_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Source namespace not found or inactive: ' || P_SOURCE_NAMESPACE);
    END IF;

    -- Lookup target namespace
    SELECT NAMESPACE_ID INTO :v_target_ns_id
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES
    WHERE NAMESPACE_NAME = :P_TARGET_NAMESPACE AND STATUS = 'ACTIVE';

    IF (v_target_ns_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Target namespace not found or inactive: ' || P_TARGET_NAMESPACE);
    END IF;

    -- Check transcode policy
    v_policy_result := ENTITY_VAULT_DB.POLICY.FN_CHECK_TRANSCODE_POLICY(v_source_ns_id, v_target_ns_id);

    IF (v_policy_result = 'DENY') THEN
        CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
            'TRANSCODE', NULL, :v_source_ns_id, :v_target_ns_id, NULL,
            OBJECT_CONSTRUCT('encoded_id', P_ENCODED_ID), NULL, NULL, NULL, NULL, 'DENIED'
        );
        RETURN OBJECT_CONSTRUCT('error', 'Transcode policy denied', 'policy_result', 'DENIED');
    END IF;

    -- Reverse-lookup entity_id from encoded_id + source namespace
    SELECT ENTITY_ID INTO :v_entity_id
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS
    WHERE ENCODED_ID = :P_ENCODED_ID AND NAMESPACE_ID = :v_source_ns_id;

    IF (v_entity_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Encoded ID not found in source namespace');
    END IF;

    -- Check suppression
    v_is_suppressed := ENTITY_VAULT_DB.POLICY.FN_CHECK_SUPPRESSION(v_entity_id, 'TRANSCODE');
    IF (v_is_suppressed) THEN
        CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
            'TRANSCODE', :v_entity_id, :v_source_ns_id, :v_target_ns_id, NULL,
            NULL, NULL, NULL, NULL, NULL, 'SUPPRESSED'
        );
        RETURN OBJECT_CONSTRUCT('error', 'Entity is suppressed for transcoding', 'policy_result', 'SUPPRESSED');
    END IF;

    -- If policy requires consent, check consent records
    IF (v_policy_result = 'REQUIRE_CONSENT') THEN
        v_has_consent := ENTITY_VAULT_DB.POLICY.FN_CHECK_CONSENT(v_entity_id, v_target_ns_id, 'TRANSCODE');
        IF (NOT v_has_consent) THEN
            CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
                'TRANSCODE', :v_entity_id, :v_source_ns_id, :v_target_ns_id, NULL,
                NULL, NULL, NULL, NULL, NULL, 'NO_CONSENT'
            );
            RETURN OBJECT_CONSTRUCT('error', 'Consent required but not found', 'policy_result', 'NO_CONSENT');
        END IF;
    END IF;

    -- Check if target encoding already exists
    SELECT ENCODED_ID INTO :v_existing_target_encoded
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS
    WHERE ENTITY_ID = :v_entity_id AND NAMESPACE_ID = :v_target_ns_id;

    IF (v_existing_target_encoded IS NOT NULL) THEN
        v_target_encoded_id := v_existing_target_encoded;
    ELSE
        -- Get active HMAC key for target namespace
        SELECT KEY_VERSION_ID, HMAC_SECRET_ENCRYPTED
        INTO :v_target_key_version_id, :v_target_hmac_secret
        FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_KEY_VERSIONS
        WHERE NAMESPACE_ID = :v_target_ns_id AND IS_ACTIVE = TRUE
        ORDER BY VERSION_NUMBER DESC
        LIMIT 1;

        IF (v_target_key_version_id IS NULL) THEN
            RETURN OBJECT_CONSTRUCT('error', 'No active HMAC key for target namespace: ' || P_TARGET_NAMESPACE);
        END IF;

        -- Compute target encoded_id
        v_target_encoded_id := SHA2(CONCAT(v_target_hmac_secret, ':', v_entity_id));

        -- Cache in NAMESPACE_ENCODINGS
        INSERT INTO ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS (
            ENCODING_ID, ENTITY_ID, NAMESPACE_ID, ENCODED_ID, KEY_VERSION_ID
        )
        SELECT UUID_STRING(), :v_entity_id, :v_target_ns_id, :v_target_encoded_id, :v_target_key_version_id;
    END IF;

    -- Audit
    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
        'TRANSCODE', :v_entity_id, :v_source_ns_id, :v_target_ns_id, NULL,
        OBJECT_CONSTRUCT('encoded_id', P_ENCODED_ID),
        OBJECT_CONSTRUCT('target_encoded_id', v_target_encoded_id),
        NULL, NULL, NULL, 'ALLOW'
    );

    v_result := OBJECT_CONSTRUCT(
        'target_encoded_id', v_target_encoded_id,
        'source_namespace', P_SOURCE_NAMESPACE,
        'target_namespace', P_TARGET_NAMESPACE,
        'policy_result', v_policy_result
    );
    RETURN v_result;
END;

-- =============================================================================
-- ENRICHMENT: SP_ENRICH_OUT
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.ENRICHMENT.SP_ENRICH_OUT(
    P_ENCODED_IDS VARIANT,
    P_NAMESPACE_NAME VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_namespace_id VARCHAR;
    v_clearance VARCHAR;
    v_results VARIANT DEFAULT PARSE_JSON('[]');
    v_total INTEGER;
    v_matched INTEGER DEFAULT 0;
    v_unmatched INTEGER DEFAULT 0;
    v_result VARIANT;
BEGIN
    -- Lookup namespace
    SELECT NAMESPACE_ID, CLEARANCE_LEVEL
    INTO :v_namespace_id, :v_clearance
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES
    WHERE NAMESPACE_NAME = :P_NAMESPACE_NAME AND STATUS = 'ACTIVE';

    IF (v_namespace_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Namespace not found or inactive: ' || P_NAMESPACE_NAME);
    END IF;

    v_total := ARRAY_SIZE(P_ENCODED_IDS);

    -- Process each encoded_id
    LET i INTEGER := 0;
    WHILE (i < v_total) DO
        LET enc_id VARCHAR := P_ENCODED_IDS[i]::VARCHAR;
        LET entity_id VARCHAR;
        LET entity_type VARCHAR;
        LET entity_metadata VARIANT;

        -- Reverse-map encoded_id to entity_id
        SELECT ne.ENTITY_ID INTO :entity_id
        FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS ne
        WHERE ne.ENCODED_ID = :enc_id AND ne.NAMESPACE_ID = :v_namespace_id;

        IF (entity_id IS NULL) THEN
            v_unmatched := v_unmatched + 1;
            v_results := ARRAY_APPEND(v_results, OBJECT_CONSTRUCT(
                'encoded_id', enc_id,
                'matched', FALSE,
                'metadata', NULL,
                'groups', PARSE_JSON('[]'),
                'contributions', PARSE_JSON('[]')
            ));
        ELSE
            v_matched := v_matched + 1;

            -- Get entity metadata and type
            SELECT ENTITY_TYPE, METADATA
            INTO :entity_type, :entity_metadata
            FROM ENTITY_VAULT_DB.CORE.ENTITIES
            WHERE ENTITY_ID = :entity_id;

            -- Filter metadata by clearance level using entity_type_schemas
            LET filtered_metadata VARIANT := PARSE_JSON('{}');
            LET schema_attrs VARIANT;

            SELECT ATTRIBUTES INTO :schema_attrs
            FROM ENTITY_VAULT_DB.CORE.ENTITY_TYPE_SCHEMAS
            WHERE CLASS_NAME = :entity_type;

            IF (schema_attrs IS NOT NULL) THEN
                -- Build filtered metadata based on clearance
                LET attr_idx INTEGER := 0;
                LET attr_count INTEGER := ARRAY_SIZE(schema_attrs);
                WHILE (attr_idx < attr_count) DO
                    LET field_name VARCHAR := schema_attrs[attr_idx]:property_name::VARCHAR;
                    LET field_class VARCHAR := COALESCE(schema_attrs[attr_idx]:classification::VARCHAR, 'ENRICHMENT');
                    LET can_access BOOLEAN := ENTITY_VAULT_DB.POLICY.FN_CHECK_CLEARANCE(v_clearance, field_class);

                    IF (can_access AND entity_metadata[field_name] IS NOT NULL) THEN
                        filtered_metadata := OBJECT_INSERT(filtered_metadata, field_name, entity_metadata[field_name]);
                    END IF;
                    attr_idx := attr_idx + 1;
                END WHILE;
            ELSE
                -- No schema defined; return all metadata at ENRICHMENT level
                filtered_metadata := entity_metadata;
            END IF;

            -- Get group memberships the namespace has access to
            LET groups_array VARIANT := PARSE_JSON('[]');
            LET group_cursor CURSOR FOR
                SELECT eg.GROUP_NAME, egm.CATEGORY_VALUE
                FROM ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUP_MEMBERS egm
                JOIN ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUPS eg ON egm.GROUP_ID = eg.GROUP_ID
                WHERE egm.ENTITY_ID = :entity_id
                  AND (eg.CREATED_BY_NAMESPACE_ID = :v_namespace_id
                       OR EXISTS (
                           SELECT 1 FROM ENTITY_VAULT_DB.ENRICHMENT.GROUP_ACCESS_GRANTS gag
                           WHERE gag.GROUP_ID = eg.GROUP_ID
                             AND gag.NAMESPACE_ID = :v_namespace_id
                             AND gag.STATUS = 'ACTIVE'
                       ));

            FOR rec IN group_cursor DO
                groups_array := ARRAY_APPEND(groups_array, OBJECT_CONSTRUCT(
                    'group_name', rec.GROUP_NAME,
                    'category_value', rec.CATEGORY_VALUE
                ));
            END FOR;

            -- Get contributions the namespace has access to
            LET contribs_array VARIANT := PARSE_JSON('[]');
            LET contrib_cursor CURSOR FOR
                SELECT cs.SCHEMA_NAME, ec.ATTRIBUTES, TO_VARCHAR(ec.CONTRIBUTED_AT, 'YYYY-MM-DD HH24:MI:SS') AS CONTRIB_AT
                FROM ENTITY_VAULT_DB.ENRICHMENT.ENTITY_CONTRIBUTIONS ec
                JOIN ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_SCHEMAS cs ON ec.SCHEMA_ID = cs.SCHEMA_ID
                WHERE ec.ENTITY_ID = :entity_id
                  AND (cs.NAMESPACE_ID = :v_namespace_id
                       OR EXISTS (
                           SELECT 1 FROM ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_ACCESS_GRANTS cag
                           WHERE cag.SCHEMA_ID = cs.SCHEMA_ID
                             AND cag.NAMESPACE_ID = :v_namespace_id
                             AND cag.STATUS = 'ACTIVE'
                       ))
                QUALIFY ROW_NUMBER() OVER (PARTITION BY ec.SCHEMA_ID ORDER BY ec.CONTRIBUTED_AT DESC) = 1;

            FOR crec IN contrib_cursor DO
                contribs_array := ARRAY_APPEND(contribs_array, OBJECT_CONSTRUCT(
                    'schema_name', crec.SCHEMA_NAME,
                    'attributes', crec.ATTRIBUTES,
                    'contributed_at', crec.CONTRIB_AT
                ));
            END FOR;

            v_results := ARRAY_APPEND(v_results, OBJECT_CONSTRUCT(
                'encoded_id', enc_id,
                'matched', TRUE,
                'metadata', filtered_metadata,
                'groups', groups_array,
                'contributions', contribs_array
            ));
        END IF;
        i := i + 1;
    END WHILE;

    -- Audit
    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
        'ENRICH_OUT', NULL, :v_namespace_id, NULL, NULL,
        OBJECT_CONSTRUCT('count', v_total),
        OBJECT_CONSTRUCT('matched', v_matched, 'unmatched', v_unmatched),
        NULL, NULL, NULL, 'ALLOW'
    );

    v_result := OBJECT_CONSTRUCT(
        'results', v_results,
        'summary', OBJECT_CONSTRUCT('total', v_total, 'matched', v_matched, 'unmatched', v_unmatched)
    );
    RETURN v_result;
END;

-- =============================================================================
-- ENRICHMENT: SP_ENRICH_IN
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.ENRICHMENT.SP_ENRICH_IN(
    P_GROUP_NAME VARCHAR,
    P_GROUP_DESCRIPTION VARCHAR,
    P_ENTITY_TYPE VARCHAR,
    P_CATEGORY_SCHEMA VARIANT,
    P_NAMESPACE_NAME VARCHAR,
    P_MEMBERS VARIANT
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_namespace_id VARCHAR;
    v_group_id VARCHAR;
    v_existing_group_ns VARCHAR;
    v_members_added INTEGER DEFAULT 0;
    v_already_existed INTEGER DEFAULT 0;
    v_unmatched INTEGER DEFAULT 0;
    v_result VARIANT;
BEGIN
    -- Lookup namespace
    SELECT NAMESPACE_ID INTO :v_namespace_id
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES
    WHERE NAMESPACE_NAME = :P_NAMESPACE_NAME AND STATUS = 'ACTIVE';

    IF (v_namespace_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Namespace not found or inactive: ' || P_NAMESPACE_NAME);
    END IF;

    -- Check if group exists
    SELECT GROUP_ID, CREATED_BY_NAMESPACE_ID
    INTO :v_group_id, :v_existing_group_ns
    FROM ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUPS
    WHERE GROUP_NAME = :P_GROUP_NAME;

    IF (v_group_id IS NOT NULL AND v_existing_group_ns != v_namespace_id) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Group name already exists and is owned by another namespace');
    END IF;

    -- Create group if it doesn't exist
    IF (v_group_id IS NULL) THEN
        v_group_id := UUID_STRING();
        INSERT INTO ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUPS (
            GROUP_ID, GROUP_NAME, GROUP_DESCRIPTION, ENTITY_TYPE,
            CREATED_BY_NAMESPACE_ID, CATEGORY_SCHEMA
        )
        SELECT :v_group_id, :P_GROUP_NAME, :P_GROUP_DESCRIPTION, :P_ENTITY_TYPE,
               :v_namespace_id, :P_CATEGORY_SCHEMA;
    END IF;

    -- Process members
    LET member_count INTEGER := ARRAY_SIZE(P_MEMBERS);
    LET i INTEGER := 0;

    WHILE (i < member_count) DO
        LET enc_id VARCHAR := P_MEMBERS[i]:encoded_id::VARCHAR;
        LET cat_value VARCHAR := P_MEMBERS[i]:category_value::VARCHAR;
        LET entity_id VARCHAR;

        -- Reverse-map encoded_id to entity_id
        SELECT ne.ENTITY_ID INTO :entity_id
        FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS ne
        WHERE ne.ENCODED_ID = :enc_id AND ne.NAMESPACE_ID = :v_namespace_id;

        IF (entity_id IS NULL) THEN
            v_unmatched := v_unmatched + 1;
        ELSE
            -- Check if already a member
            LET existing_member VARCHAR;
            SELECT MEMBER_ID INTO :existing_member
            FROM ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUP_MEMBERS
            WHERE GROUP_ID = :v_group_id AND ENTITY_ID = :entity_id;

            IF (existing_member IS NOT NULL) THEN
                v_already_existed := v_already_existed + 1;
            ELSE
                INSERT INTO ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUP_MEMBERS (
                    MEMBER_ID, GROUP_ID, ENTITY_ID, CATEGORY_VALUE, ASSIGNED_BY_NAMESPACE_ID
                )
                SELECT UUID_STRING(), :v_group_id, :entity_id, :cat_value, :v_namespace_id;
                v_members_added := v_members_added + 1;
            END IF;
        END IF;
        i := i + 1;
    END WHILE;

    -- Audit
    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
        'ENRICH_IN', NULL, :v_namespace_id, NULL, :v_group_id,
        OBJECT_CONSTRUCT('group_name', P_GROUP_NAME, 'member_count', member_count),
        OBJECT_CONSTRUCT('added', v_members_added, 'existed', v_already_existed, 'unmatched', v_unmatched),
        NULL, NULL, NULL, 'ALLOW'
    );

    v_result := OBJECT_CONSTRUCT(
        'group_id', v_group_id,
        'group_name', P_GROUP_NAME,
        'members_added', v_members_added,
        'already_existed', v_already_existed,
        'unmatched', v_unmatched
    );
    RETURN v_result;
END;

-- =============================================================================
-- ENRICHMENT: SP_LIST_GROUPS
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.ENRICHMENT.SP_LIST_GROUPS(
    P_ENTITY_TYPE VARCHAR DEFAULT NULL
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_groups VARIANT DEFAULT PARSE_JSON('[]');
    v_result VARIANT;
BEGIN
    LET group_cursor CURSOR FOR
        SELECT
            eg.GROUP_ID,
            eg.GROUP_NAME,
            eg.GROUP_DESCRIPTION,
            eg.ENTITY_TYPE,
            eg.CATEGORY_SCHEMA,
            n.NAMESPACE_NAME AS CREATED_BY,
            TO_VARCHAR(eg.CREATED_AT, 'YYYY-MM-DD HH24:MI:SS') AS CREATED_AT,
            (SELECT COUNT(*) FROM ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUP_MEMBERS egm WHERE egm.GROUP_ID = eg.GROUP_ID) AS MEMBER_COUNT
        FROM ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUPS eg
        JOIN ENTITY_VAULT_DB.ENCODING.NAMESPACES n ON eg.CREATED_BY_NAMESPACE_ID = n.NAMESPACE_ID
        WHERE eg.IS_DISCOVERABLE = TRUE
          AND eg.STATUS = 'ACTIVE'
          AND (:P_ENTITY_TYPE IS NULL OR eg.ENTITY_TYPE = :P_ENTITY_TYPE)
        ORDER BY eg.CREATED_AT DESC;

    FOR rec IN group_cursor DO
        v_groups := ARRAY_APPEND(v_groups, OBJECT_CONSTRUCT(
            'group_id', rec.GROUP_ID,
            'group_name', rec.GROUP_NAME,
            'group_description', rec.GROUP_DESCRIPTION,
            'entity_type', rec.ENTITY_TYPE,
            'category_schema', rec.CATEGORY_SCHEMA,
            'created_by', rec.CREATED_BY,
            'created_at', rec.CREATED_AT,
            'member_count', rec.MEMBER_COUNT
        ));
    END FOR;

    v_result := OBJECT_CONSTRUCT('groups', v_groups);
    RETURN v_result;
END;

-- =============================================================================
-- ENRICHMENT: SP_REQUEST_GROUP_ACCESS
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.ENRICHMENT.SP_REQUEST_GROUP_ACCESS(
    P_GROUP_ID VARCHAR,
    P_NAMESPACE_NAME VARCHAR,
    P_ACCESS_LEVEL VARCHAR DEFAULT 'READ'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_namespace_id VARCHAR;
    v_group_exists BOOLEAN;
    v_group_owner_ns VARCHAR;
    v_existing_grant VARCHAR;
    v_grant_id VARCHAR;
    v_result VARIANT;
BEGIN
    -- Lookup namespace
    SELECT NAMESPACE_ID INTO :v_namespace_id
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES
    WHERE NAMESPACE_NAME = :P_NAMESPACE_NAME AND STATUS = 'ACTIVE';

    IF (v_namespace_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Namespace not found or inactive: ' || P_NAMESPACE_NAME);
    END IF;

    -- Verify group exists
    SELECT TRUE, CREATED_BY_NAMESPACE_ID
    INTO :v_group_exists, :v_group_owner_ns
    FROM ENTITY_VAULT_DB.ENRICHMENT.ENTITY_GROUPS
    WHERE GROUP_ID = :P_GROUP_ID AND STATUS = 'ACTIVE';

    IF (v_group_exists IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Group not found or inactive');
    END IF;

    -- Check if grant already exists
    SELECT GRANT_ID INTO :v_existing_grant
    FROM ENTITY_VAULT_DB.ENRICHMENT.GROUP_ACCESS_GRANTS
    WHERE GROUP_ID = :P_GROUP_ID AND NAMESPACE_ID = :v_namespace_id AND STATUS = 'ACTIVE';

    IF (v_existing_grant IS NOT NULL) THEN
        RETURN OBJECT_CONSTRUCT('message', 'Access already granted', 'grant_id', v_existing_grant);
    END IF;

    -- Create access grant
    v_grant_id := UUID_STRING();
    INSERT INTO ENTITY_VAULT_DB.ENRICHMENT.GROUP_ACCESS_GRANTS (
        GRANT_ID, GROUP_ID, NAMESPACE_ID, ACCESS_LEVEL, GRANTED_BY_NAMESPACE_ID
    )
    SELECT :v_grant_id, :P_GROUP_ID, :v_namespace_id, :P_ACCESS_LEVEL, :v_group_owner_ns;

    -- Audit
    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
        'GROUP_ACCESS_GRANT', NULL, :v_namespace_id, NULL, :P_GROUP_ID,
        OBJECT_CONSTRUCT('access_level', P_ACCESS_LEVEL),
        OBJECT_CONSTRUCT('grant_id', v_grant_id),
        NULL, NULL, NULL, 'ALLOW'
    );

    v_result := OBJECT_CONSTRUCT(
        'grant_id', v_grant_id,
        'group_id', P_GROUP_ID,
        'namespace', P_NAMESPACE_NAME,
        'access_level', P_ACCESS_LEVEL,
        'status', 'ACTIVE'
    );
    RETURN v_result;
END;

-- =============================================================================
-- ENRICHMENT: SP_CREATE_CONTRIBUTION_SCHEMA
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.ENRICHMENT.SP_CREATE_CONTRIBUTION_SCHEMA(
    P_SCHEMA_NAME VARCHAR,
    P_DESCRIPTION VARCHAR,
    P_ENTITY_TYPE VARCHAR,
    P_NAMESPACE_NAME VARCHAR,
    P_FIELD_DEFINITIONS VARIANT
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_namespace_id VARCHAR;
    v_schema_id VARCHAR;
    v_existing_schema VARCHAR;
    v_result VARIANT;
BEGIN
    -- Lookup namespace
    SELECT NAMESPACE_ID INTO :v_namespace_id
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES
    WHERE NAMESPACE_NAME = :P_NAMESPACE_NAME AND STATUS = 'ACTIVE';

    IF (v_namespace_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Namespace not found or inactive: ' || P_NAMESPACE_NAME);
    END IF;

    -- Check if schema name already exists
    SELECT SCHEMA_ID INTO :v_existing_schema
    FROM ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_SCHEMAS
    WHERE SCHEMA_NAME = :P_SCHEMA_NAME;

    IF (v_existing_schema IS NOT NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Contribution schema already exists: ' || P_SCHEMA_NAME);
    END IF;

    -- Create schema
    v_schema_id := UUID_STRING();
    INSERT INTO ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_SCHEMAS (
        SCHEMA_ID, SCHEMA_NAME, DESCRIPTION, ENTITY_TYPE, NAMESPACE_ID, FIELD_DEFINITIONS
    )
    SELECT :v_schema_id, :P_SCHEMA_NAME, :P_DESCRIPTION, :P_ENTITY_TYPE, :v_namespace_id, :P_FIELD_DEFINITIONS;

    -- Audit
    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
        'CREATE_CONTRIBUTION_SCHEMA', NULL, :v_namespace_id, NULL, NULL,
        OBJECT_CONSTRUCT('schema_name', P_SCHEMA_NAME, 'entity_type', P_ENTITY_TYPE),
        OBJECT_CONSTRUCT('schema_id', v_schema_id),
        NULL, NULL, NULL, 'ALLOW'
    );

    v_result := OBJECT_CONSTRUCT(
        'schema_id', v_schema_id,
        'schema_name', P_SCHEMA_NAME,
        'entity_type', P_ENTITY_TYPE,
        'namespace', P_NAMESPACE_NAME
    );
    RETURN v_result;
END;

-- =============================================================================
-- ENRICHMENT: SP_CONTRIBUTE
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.ENRICHMENT.SP_CONTRIBUTE(
    P_SCHEMA_NAME VARCHAR,
    P_NAMESPACE_NAME VARCHAR,
    P_CONTRIBUTIONS VARIANT
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_namespace_id VARCHAR;
    v_schema_id VARCHAR;
    v_contributed INTEGER DEFAULT 0;
    v_unmatched INTEGER DEFAULT 0;
    v_result VARIANT;
BEGIN
    -- Lookup namespace
    SELECT NAMESPACE_ID INTO :v_namespace_id
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES
    WHERE NAMESPACE_NAME = :P_NAMESPACE_NAME AND STATUS = 'ACTIVE';

    IF (v_namespace_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Namespace not found or inactive: ' || P_NAMESPACE_NAME);
    END IF;

    -- Lookup schema
    SELECT SCHEMA_ID INTO :v_schema_id
    FROM ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_SCHEMAS
    WHERE SCHEMA_NAME = :P_SCHEMA_NAME AND STATUS = 'ACTIVE';

    IF (v_schema_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Contribution schema not found or inactive: ' || P_SCHEMA_NAME);
    END IF;

    -- Process contributions
    LET contrib_count INTEGER := ARRAY_SIZE(P_CONTRIBUTIONS);
    LET i INTEGER := 0;

    WHILE (i < contrib_count) DO
        LET enc_id VARCHAR := P_CONTRIBUTIONS[i]:encoded_id::VARCHAR;
        LET attrs VARIANT := P_CONTRIBUTIONS[i]:attributes;
        LET entity_id VARCHAR;

        -- Reverse-map encoded_id to entity_id
        SELECT ne.ENTITY_ID INTO :entity_id
        FROM ENTITY_VAULT_DB.ENCODING.NAMESPACE_ENCODINGS ne
        WHERE ne.ENCODED_ID = :enc_id AND ne.NAMESPACE_ID = :v_namespace_id;

        IF (entity_id IS NULL) THEN
            v_unmatched := v_unmatched + 1;
        ELSE
            INSERT INTO ENTITY_VAULT_DB.ENRICHMENT.ENTITY_CONTRIBUTIONS (
                CONTRIBUTION_ID, ENTITY_ID, SCHEMA_ID, NAMESPACE_ID, ATTRIBUTES
            )
            SELECT UUID_STRING(), :entity_id, :v_schema_id, :v_namespace_id, :attrs;
            v_contributed := v_contributed + 1;
        END IF;
        i := i + 1;
    END WHILE;

    -- Audit
    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
        'CONTRIBUTE', NULL, :v_namespace_id, NULL, NULL,
        OBJECT_CONSTRUCT('schema_name', P_SCHEMA_NAME, 'count', contrib_count),
        OBJECT_CONSTRUCT('contributed', v_contributed, 'unmatched', v_unmatched),
        NULL, NULL, NULL, 'ALLOW'
    );

    v_result := OBJECT_CONSTRUCT(
        'schema_name', P_SCHEMA_NAME,
        'contributed', v_contributed,
        'unmatched', v_unmatched
    );
    RETURN v_result;
END;

-- =============================================================================
-- ENRICHMENT: SP_LIST_CONTRIBUTION_SCHEMAS
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.ENRICHMENT.SP_LIST_CONTRIBUTION_SCHEMAS(
    P_ENTITY_TYPE VARCHAR DEFAULT NULL
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_schemas VARIANT DEFAULT PARSE_JSON('[]');
    v_result VARIANT;
BEGIN
    LET schema_cursor CURSOR FOR
        SELECT
            cs.SCHEMA_ID,
            cs.SCHEMA_NAME,
            cs.DESCRIPTION,
            cs.ENTITY_TYPE,
            cs.FIELD_DEFINITIONS,
            n.NAMESPACE_NAME AS CREATED_BY,
            TO_VARCHAR(cs.CREATED_AT, 'YYYY-MM-DD HH24:MI:SS') AS CREATED_AT,
            (SELECT COUNT(*) FROM ENTITY_VAULT_DB.ENRICHMENT.ENTITY_CONTRIBUTIONS ec WHERE ec.SCHEMA_ID = cs.SCHEMA_ID) AS CONTRIBUTION_COUNT
        FROM ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_SCHEMAS cs
        JOIN ENTITY_VAULT_DB.ENCODING.NAMESPACES n ON cs.NAMESPACE_ID = n.NAMESPACE_ID
        WHERE cs.IS_DISCOVERABLE = TRUE
          AND cs.STATUS = 'ACTIVE'
          AND (:P_ENTITY_TYPE IS NULL OR cs.ENTITY_TYPE = :P_ENTITY_TYPE)
        ORDER BY cs.CREATED_AT DESC;

    FOR rec IN schema_cursor DO
        v_schemas := ARRAY_APPEND(v_schemas, OBJECT_CONSTRUCT(
            'schema_id', rec.SCHEMA_ID,
            'schema_name', rec.SCHEMA_NAME,
            'description', rec.DESCRIPTION,
            'entity_type', rec.ENTITY_TYPE,
            'field_definitions', rec.FIELD_DEFINITIONS,
            'created_by', rec.CREATED_BY,
            'created_at', rec.CREATED_AT,
            'contribution_count', rec.CONTRIBUTION_COUNT
        ));
    END FOR;

    v_result := OBJECT_CONSTRUCT('schemas', v_schemas);
    RETURN v_result;
END;

-- =============================================================================
-- ENRICHMENT: SP_REQUEST_CONTRIBUTION_ACCESS
-- =============================================================================

CREATE OR REPLACE PROCEDURE ENTITY_VAULT_DB.ENRICHMENT.SP_REQUEST_CONTRIBUTION_ACCESS(
    P_SCHEMA_ID VARCHAR,
    P_NAMESPACE_NAME VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_namespace_id VARCHAR;
    v_schema_owner_ns VARCHAR;
    v_schema_exists BOOLEAN;
    v_existing_grant VARCHAR;
    v_grant_id VARCHAR;
    v_result VARIANT;
BEGIN
    -- Lookup namespace
    SELECT NAMESPACE_ID INTO :v_namespace_id
    FROM ENTITY_VAULT_DB.ENCODING.NAMESPACES
    WHERE NAMESPACE_NAME = :P_NAMESPACE_NAME AND STATUS = 'ACTIVE';

    IF (v_namespace_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Namespace not found or inactive: ' || P_NAMESPACE_NAME);
    END IF;

    -- Verify schema exists
    SELECT TRUE, NAMESPACE_ID
    INTO :v_schema_exists, :v_schema_owner_ns
    FROM ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_SCHEMAS
    WHERE SCHEMA_ID = :P_SCHEMA_ID AND STATUS = 'ACTIVE';

    IF (v_schema_exists IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Contribution schema not found or inactive');
    END IF;

    -- Check if grant already exists
    SELECT GRANT_ID INTO :v_existing_grant
    FROM ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_ACCESS_GRANTS
    WHERE SCHEMA_ID = :P_SCHEMA_ID AND NAMESPACE_ID = :v_namespace_id AND STATUS = 'ACTIVE';

    IF (v_existing_grant IS NOT NULL) THEN
        RETURN OBJECT_CONSTRUCT('message', 'Access already granted', 'grant_id', v_existing_grant);
    END IF;

    -- Create access grant
    v_grant_id := UUID_STRING();
    INSERT INTO ENTITY_VAULT_DB.ENRICHMENT.CONTRIBUTION_ACCESS_GRANTS (
        GRANT_ID, SCHEMA_ID, NAMESPACE_ID, ACCESS_LEVEL, GRANTED_BY_NAMESPACE_ID
    )
    SELECT :v_grant_id, :P_SCHEMA_ID, :v_namespace_id, 'READ', :v_schema_owner_ns;

    -- Audit
    CALL ENTITY_VAULT_DB.AUDIT.SP_LOG_AUDIT(
        'CONTRIBUTION_ACCESS_GRANT', NULL, :v_namespace_id, NULL, NULL,
        OBJECT_CONSTRUCT('schema_id', P_SCHEMA_ID),
        OBJECT_CONSTRUCT('grant_id', v_grant_id),
        NULL, NULL, NULL, 'ALLOW'
    );

    v_result := OBJECT_CONSTRUCT(
        'grant_id', v_grant_id,
        'schema_id', P_SCHEMA_ID,
        'namespace', P_NAMESPACE_NAME,
        'access_level', 'READ',
        'status', 'ACTIVE'
    );
    RETURN v_result;
END;
