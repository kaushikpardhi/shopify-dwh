
CREATE OR REPLACE PROCEDURE {{ DB_NAME }}.SQL_PRACTICE.LOAD_DIM_PRODUCT()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    -- One ID for the complete pipeline execution
    V_RUN_ID VARCHAR DEFAULT UUID_STRING();

    -- Current step and timing
    V_CURRENT_STEP VARCHAR DEFAULT 'DIM_PRODUCT';
    V_STEP_START_TIME TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP();
    V_STEP_END_TIME TIMESTAMP_TZ;

    -- Dimension metrics
    V_DIM_ROWS_INSERTED NUMBER DEFAULT 0;
    V_DIM_ROWS_UPDATED NUMBER DEFAULT 0;

    -- Fact metrics
    V_FACT_ROWS_INSERTED NUMBER DEFAULT 0;
    V_FACT_ROWS_UPDATED NUMBER DEFAULT 0;

    -- Error details
    V_ERROR_CODE VARCHAR;
    V_ERROR_MESSAGE VARCHAR;
    V_QUERY_ID VARCHAR;

    V_CUSTOMER_ROWS_INSERTED NUMBER DEFAULT 0;
    V_CUSTOMER_ROWS_UPDATED NUMBER DEFAULT 0;

BEGIN

        --------------------------------------------------
    -- STEP 1: LOAD DIM_CUSTOMER (SCD TYPE 2)
    --------------------------------------------------

    V_CURRENT_STEP := 'DIM_CUSTOMER';
    V_STEP_START_TIME := CURRENT_TIMESTAMP();

    -- Expire changed current customer records
    UPDATE {{ DB_NAME }}.SQL_PRACTICE.DIM_CUSTOMER D
    SET
        IS_CURRENT = FALSE,
        RECORD_END_DATE = CURRENT_TIMESTAMP()
    FROM {{ DB_NAME }}.SQL_PRACTICE.STG_CUSTOMERS S
    WHERE D.CUSTOMER_ID = S.ID
      AND D.IS_CURRENT = TRUE
      AND (
           NVL(D.FIRST_NAME, '') <> NVL(S.FIRST_NAME, '')
        OR NVL(D.LAST_NAME, '') <> NVL(S.LAST_NAME, '')
        OR NVL(D.EMAIL, '') <> NVL(S.EMAIL, '')
        OR NVL(D.PHONE, '') <> NVL(S.PHONE, '')
        OR NVL(D.CITY, '') <> NVL(S.CITY, '')
        OR NVL(D.STATE, '') <> NVL(S.STATE, '')
        OR NVL(D.DEFAULT_STATE, '') <> NVL(S.DEFAULT_STATE, '')
        OR NVL(D.COUNTRY, '') <> NVL(S.COUNTRY, '')
        OR NVL(D.ZIP, '') <> NVL(S.ZIP, '')
      );

    V_CUSTOMER_ROWS_UPDATED := SQLROWCOUNT;

    -- Insert new customers and new versions of changed customers
    INSERT INTO {{ DB_NAME }}.SQL_PRACTICE.DIM_CUSTOMER
    (
        CUSTOMER_SK,
        CUSTOMER_ID,
        FIRST_NAME,
        LAST_NAME,
        EMAIL,
        PHONE,
        CITY,
        STATE,
        DEFAULT_STATE,
        COUNTRY,
        ZIP,
        CREATED_AT,
        UPDATED_AT,
        RECORD_START_DATE,
        RECORD_END_DATE,
        IS_CURRENT,
        LOAD_DATE
    )
    SELECT
        (
            SELECT COALESCE(MAX(CUSTOMER_SK), 0)
            FROM {{ DB_NAME }}.SQL_PRACTICE.DIM_CUSTOMER
        ) + ROW_NUMBER() OVER (ORDER BY S.ID),
        S.ID,
        S.FIRST_NAME,
        S.LAST_NAME,
        S.EMAIL,
        S.PHONE,
        S.CITY,
        S.STATE,
        S.DEFAULT_STATE,
        S.COUNTRY,
        S.ZIP,
        S.CREATED_AT,
        S.UPDATED_AT,
        CURRENT_TIMESTAMP(),
        '9999-12-31'::TIMESTAMP_TZ,
        TRUE,
        CURRENT_TIMESTAMP()
    FROM {{ DB_NAME }}.SQL_PRACTICE.STG_CUSTOMERS S
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM {{ DB_NAME }}.SQL_PRACTICE.DIM_CUSTOMER D
        WHERE D.CUSTOMER_ID = S.ID
          AND D.IS_CURRENT = TRUE
    );

    V_CUSTOMER_ROWS_INSERTED := SQLROWCOUNT;
    V_STEP_END_TIME := CURRENT_TIMESTAMP();

    -- Audit successful customer load
    INSERT INTO {{ DB_NAME }}.SQL_PRACTICE.ETL_AUDIT_LOG
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
        'DIM_CUSTOMER',
        'SUCCESS',
        :V_CUSTOMER_ROWS_INSERTED,
        :V_CUSTOMER_ROWS_UPDATED,
        :V_STEP_START_TIME,
        :V_STEP_END_TIME,
        NULL
    );
    --------------------------------------------------
    -- STEP 2: LOAD DIM_PRODUCT
    --------------------------------------------------

    V_CURRENT_STEP := 'DIM_PRODUCT';
    V_STEP_START_TIME := CURRENT_TIMESTAMP();

    -- Expire changed current versions
    UPDATE {{ DB_NAME }}.SQL_PRACTICE.DIM_PRODUCT D
    SET
        IS_CURRENT = FALSE,
        RECORD_END_DATE = CURRENT_TIMESTAMP()
    FROM {{ DB_NAME }}.SQL_PRACTICE.STG_PRODUCTS S
    WHERE D.PRODUCT_ID = S.ID
      AND D.IS_CURRENT = TRUE
      AND (
           NVL(D.TITLE, '') <> NVL(S.TITLE, '')
        OR NVL(D.HANDLE, '') <> NVL(S.HANDLE, '')
        OR NVL(D.VENDOR, '') <> NVL(S.VENDOR, '')
        OR NVL(D.PRODUCT_TYPE, '') <> NVL(S.PRODUCT_TYPE, '')
        OR NVL(D.STATUS, '') <> NVL(S.STATUS, '')
        OR NVL(D.TAGS, '') <> NVL(S.TAGS, '')
        OR NVL(D.IS_GIFT_CARD, FALSE)
           <> NVL(S.IS_GIFT_CARD, FALSE)
        OR NVL(D.TRACKS_INVENTORY, FALSE)
           <> NVL(S.TRACKS_INVENTORY, FALSE)
      );

    V_DIM_ROWS_UPDATED := SQLROWCOUNT;

    -- Insert new products and changed versions
    INSERT INTO {{ DB_NAME }}.SQL_PRACTICE.DIM_PRODUCT
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
    FROM {{ DB_NAME }}.SQL_PRACTICE.STG_PRODUCTS S
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM {{ DB_NAME }}.SQL_PRACTICE.DIM_PRODUCT D
        WHERE D.PRODUCT_ID = S.ID
          AND D.IS_CURRENT = TRUE
    );

    V_DIM_ROWS_INSERTED := SQLROWCOUNT;
    V_STEP_END_TIME := CURRENT_TIMESTAMP();

    -- Audit successful dimension load
    INSERT INTO {{ DB_NAME }}.SQL_PRACTICE.ETL_AUDIT_LOG
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
        'DIM_PRODUCT',
        'SUCCESS',
        :V_DIM_ROWS_INSERTED,
        :V_DIM_ROWS_UPDATED,
        :V_STEP_START_TIME,
        :V_STEP_END_TIME,
        NULL
    );


    --------------------------------------------------
    -- STEP 3: LOAD FACT_ORDER_ITEMS
    --------------------------------------------------

    V_CURRENT_STEP := 'FACT_ORDER_ITEMS';
    V_STEP_START_TIME := CURRENT_TIMESTAMP();

    -- Repair existing fact rows with missing product/date keys.
    -- Preserve already-populated keys, including historical product keys.
    UPDATE {{ DB_NAME }}.SQL_PRACTICE.FACT_ORDER_ITEMS F
    SET
        PRODUCT_SK = COALESCE(F.PRODUCT_SK, P.PRODUCT_SK),
        DATE_SK = COALESCE(F.DATE_SK, DD.DATE_SK)
    FROM {{ DB_NAME }}.SQL_PRACTICE.STG_ORDER_ITEMS S
    INNER JOIN {{ DB_NAME }}.SQL_PRACTICE.DIM_PRODUCT P
        ON S.PRODUCT_ID = P.PRODUCT_ID
       AND P.IS_CURRENT = TRUE
    INNER JOIN {{ DB_NAME }}.SQL_PRACTICE.DIM_DATE DD
        ON TO_DATE(S.ORDER_CREATED_AT) = DD.FULL_DATE
    WHERE F.LINE_ITEM_ID = S.LINE_ITEM_ID
      AND (F.PRODUCT_SK IS NULL OR F.DATE_SK IS NULL);

    V_FACT_ROWS_UPDATED := SQLROWCOUNT;

    -- Insert new order items with a date dimension key.
    INSERT INTO {{ DB_NAME }}.SQL_PRACTICE.FACT_ORDER_ITEMS
    (
        ORDER_ID,
        LINE_ITEM_ID,
        PRODUCT_SK,
        VARIANT_ID,
        QUANTITY,
        UNIT_PRICE,
        TOTAL_DISCOUNT,
        GROSS_AMOUNT,
        NET_AMOUNT,
        ORDER_CREATED_AT,
        DATE_SK
    )
    SELECT
        S.ORDER_ID,
        S.LINE_ITEM_ID,
        P.PRODUCT_SK,
        S.VARIANT_ID,
        S.QUANTITY,
        S.UNIT_PRICE,
        S.TOTAL_DISCOUNT,
        S.QUANTITY * S.UNIT_PRICE AS GROSS_AMOUNT,
        (S.QUANTITY * S.UNIT_PRICE)
            - S.TOTAL_DISCOUNT AS NET_AMOUNT,
        S.ORDER_CREATED_AT,
        DD.DATE_SK
    FROM {{ DB_NAME }}.SQL_PRACTICE.STG_ORDER_ITEMS S
    INNER JOIN {{ DB_NAME }}.SQL_PRACTICE.DIM_PRODUCT P
        ON S.PRODUCT_ID = P.PRODUCT_ID
       AND P.IS_CURRENT = TRUE
    INNER JOIN {{ DB_NAME }}.SQL_PRACTICE.DIM_DATE DD
        ON TO_DATE(S.ORDER_CREATED_AT) = DD.FULL_DATE
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM {{ DB_NAME }}.SQL_PRACTICE.FACT_ORDER_ITEMS F
        WHERE F.LINE_ITEM_ID = S.LINE_ITEM_ID
    );

    V_FACT_ROWS_INSERTED := SQLROWCOUNT;
    V_STEP_END_TIME := CURRENT_TIMESTAMP();

    -- Audit successful fact load
    INSERT INTO {{ DB_NAME }}.SQL_PRACTICE.ETL_AUDIT_LOG
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
        'FACT_ORDER_ITEMS',
        'SUCCESS',
        :V_FACT_ROWS_INSERTED,
        :V_FACT_ROWS_UPDATED,
        :V_STEP_START_TIME,
        :V_STEP_END_TIME,
        NULL
    );

    RETURN 'Pipeline completed successfully. RUN_ID='
           || V_RUN_ID;

EXCEPTION
    WHEN OTHER THEN

        V_STEP_END_TIME := CURRENT_TIMESTAMP();
        V_ERROR_CODE := SQLCODE;
        V_ERROR_MESSAGE := SQLERRM;
        V_QUERY_ID := SQLID;

        -- Record the failed step
       INSERT INTO {{ DB_NAME }}.SQL_PRACTICE.ETL_AUDIT_LOG
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
    :V_CURRENT_STEP,
    'FAILED',
    IFF(
        :V_CURRENT_STEP = 'DIM_CUSTOMER',
        :V_CUSTOMER_ROWS_INSERTED,
        IFF(
            :V_CURRENT_STEP = 'DIM_PRODUCT',
            :V_DIM_ROWS_INSERTED,
            :V_FACT_ROWS_INSERTED
        )
    ),
    IFF(
        :V_CURRENT_STEP = 'DIM_CUSTOMER',
        :V_CUSTOMER_ROWS_UPDATED,
        IFF(
            :V_CURRENT_STEP = 'DIM_PRODUCT',
            :V_DIM_ROWS_UPDATED,
            :V_FACT_ROWS_UPDATED
        )
    ),
    :V_STEP_START_TIME,
    :V_STEP_END_TIME,
    :V_ERROR_MESSAGE
);

        -- Record detailed error information
        INSERT INTO {{ DB_NAME }}.SQL_PRACTICE.ETL_ERROR_LOG
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
            :V_CURRENT_STEP,
            :V_ERROR_CODE,
            :V_ERROR_MESSAGE,
            :V_QUERY_ID
        );

        -- Do not report success after a failure
        RAISE;

END;
$$;
