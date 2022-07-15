-- migrate:up
CREATE TABLE IF NOT EXISTS sales_local ON CLUSTER '{cluster}' (
    WEEK Date32,
    COUNTRY_ID UInt64,
    REGION String,
    PRODUCT_ID Nullable(UInt64),
    UNITS Nullable(Float64),
    DOLLAR_VOLUME Nullable(Decimal(38, 10))
) ENGINE = ReplicatedMergeTree('/clickhouse/{installation}/{cluster}/tables/{shard}/{database}/{table}', '{replica}')
PARTITION BY
    toYYYYMM(WEEK)
ORDER BY
    (COUNTRY_ID, WEEK, REGION);

-- migrate:down
DROP TABLE IF EXISTS sales_local ON CLUSTER '{cluster}' SYNC;

