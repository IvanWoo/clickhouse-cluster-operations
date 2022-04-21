-- migrate:up
CREATE TABLE IF NOT EXISTS sales_local ON CLUSTER '{cluster}' (
    WEEK Date32,
    COUNTRY_ID Decimal(38, 9),
    REGION String,
    PRODUCT_ID Nullable(Decimal(38, 10)),
    UNITS Nullable(Float64),
    DOLLAR_VOLUME Nullable(Decimal(38, 10))
) ENGINE = MergeTree
PARTITION BY
    toYYYYMM(WEEK)
ORDER BY
    (COUNTRY_ID, WEEK, REGION);

-- migrate:down
DROP TABLE IF EXISTS sales_local ON CLUSTER '{cluster}';

