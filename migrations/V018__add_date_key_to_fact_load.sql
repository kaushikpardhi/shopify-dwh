
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
