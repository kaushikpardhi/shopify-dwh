
CREATE OR REPLACE PROCEDURE SQL_PRACTICE.LOAD_DIM_PRODUCT()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID VARCHAR DEFAULT UUID_STRING();
    V_STEP_NAME VARCHAR DEFAULT 'DIM_PRODUCT';
    V_START_TIME TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP();
    V_END_TIME TIMESTAMP_TZ;
    V_ROWS_INSERTED NUMBER DEFAULT 0;
    V_ROWS_UPDATED NUMBER DEFAULT 0;
    V_ERROR_CODE VARCHAR;
    V_ERROR_MESSAGE VARCHAR;
    V_QUERY_ID VARCHAR;
    V_STATUS VARCHAR DEFAULT 'SUCCESS';
BEGIN

    -- Expire changed current versions
    UPDATE SQL_PRACTICE.DIM_PRODUCT D
    SET
        IS_CURRENT = FALSE,
        RECORD_END_DATE = CURRENT_TIMESTAMP()
    FROM SQL_PRACTICE.STG_PRODUCTS S
    WHERE D.PRODUCT_ID = S.ID
      AND D.IS_CURRENT = TRUE
      AND (
           NVL(D.TITLE, '') <> NVL(S.TITLE, '')
        OR NVL(D.HANDLE, '') <> NVL(S.HANDLE, '')
        OR NVL(D.VENDOR, '') <> NVL(S.VENDOR, '')
        OR NVL(D.PRODUCT_TYPE, '') <> NVL(S.PRODUCT_TYPE, '')
        OR NVL(D.STATUS, '') <> NVL(S.STATUS, '')
        OR NVL(D.TAGS, '') <> NVL(S.TAGS, '')
        OR NVL(D.IS_GIFT_CARD, FALSE) <> NVL(S.IS_GIFT_CARD, FALSE)
        OR NVL(D.TRACKS_INVENTORY, FALSE)
           <> NVL(S.TRACKS_INVENTORY, FALSE)
      );

    V_ROWS_UPDATED := SQLROWCOUNT;

    -- Insert new products and changed versions
    INSERT INTO SQL_PRACTICE.DIM_PRODUCT
    (
        PRODUCT_ID,
        TITLE,
        HANDLE,
        VENDOR,
        PRODUCT_TYPE,
        STATUS,
        TAGS,
        IS_GIFT_CARD,
        TRACKS_INVENTORY,
        CREATED_AT,
        UPDATED_AT,
        RECORD_START_DATE,
        RECORD_END_DATE,
        IS_CURRENT
    )
    SELECT
        S.ID,
        S.TITLE,
        S.HANDLE,
        S.VENDOR,
        S.PRODUCT_TYPE,
        S.STATUS,
        S.TAGS,
        S.IS_GIFT_CARD,
        S.TRACKS_INVENTORY,
        S.CREATED_AT,
        S.UPDATED_AT,
        CURRENT_TIMESTAMP(),
        '9999-12-31'::TIMESTAMP_TZ,
        TRUE
    FROM SQL_PRACTICE.STG_PRODUCTS S
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM SQL_PRACTICE.DIM_PRODUCT D
        WHERE D.PRODUCT_ID = S.ID
          AND D.IS_CURRENT = TRUE
    );

    V_ROWS_INSERTED := SQLROWCOUNT;
    V_END_TIME := CURRENT_TIMESTAMP();

    -- Record successful execution
    INSERT INTO SQL_PRACTICE.ETL_AUDIT_LOG
    (
        RUN_ID,
        PIPELINE_NAME,
        STEP_NAME,
        STATUS,
        ROWS_INSERTED,
        ROWS_UPDATED,
        START_TIME,
        END_TIME
    )
    VALUES
    (
        :V_RUN_ID,
        'SHOPIFY_DWH',
        :V_STEP_NAME,
        'SUCCESS',
        :V_ROWS_INSERTED,
        :V_ROWS_UPDATED,
        :V_START_TIME,
        :V_END_TIME
    );

    RETURN 'DIM_PRODUCT load completed successfully. RUN_ID='
           || V_RUN_ID;

EXCEPTION
    WHEN OTHER THEN
        V_END_TIME := CURRENT_TIMESTAMP();
        V_ERROR_CODE := SQLCODE;
        V_ERROR_MESSAGE := SQLERRM;
        V_QUERY_ID := SQLID;

        -- Record failure in the audit table
        INSERT INTO SQL_PRACTICE.ETL_AUDIT_LOG
        (
            RUN_ID,
            PIPELINE_NAME,
            STEP_NAME,
            STATUS,
            ROWS_INSERTED,
            ROWS_UPDATED,
            START_TIME,
            END_TIME,
            ERROR_MESSAGE
        )
        VALUES
        (
            :V_RUN_ID,
            'SHOPIFY_DWH',
            :V_STEP_NAME,
            'FAILED',
            :V_ROWS_INSERTED,
            :V_ROWS_UPDATED,
            :V_START_TIME,
            :V_END_TIME,
            :V_ERROR_MESSAGE
        );

        -- Store detailed error information
        INSERT INTO SQL_PRACTICE.ETL_ERROR_LOG
        (
            RUN_ID,
            PIPELINE_NAME,
            STEP_NAME,
            ERROR_CODE,
            ERROR_MESSAGE,
            QUERY_ID
        )
        VALUES
        (
            :V_RUN_ID,
            'SHOPIFY_DWH',
            :V_STEP_NAME,
            :V_ERROR_CODE,
            :V_ERROR_MESSAGE,
            :V_QUERY_ID
        );

        -- Propagate the failure to the caller
        RAISE;
END;
$$;
