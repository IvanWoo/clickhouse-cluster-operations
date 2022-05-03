CREATE TABLE IF NOT EXISTS sales_local ON CLUSTER '{cluster}' (
    WEEK Date32,
    COUNTRY_ID Decimal(38, 9),
    REGION String,
    PRODUCT_ID Nullable(Decimal(38, 10)),
    UNITS Nullable(Float64),
    DOLLAR_VOLUME Nullable(Decimal(38, 10))
) ENGINE = ReplicatedMergeTree('/clickhouse/{installation}/{cluster}/tables/{shard}/{database}/{table}', '{replica}')
PARTITION BY
    toYYYYMM(WEEK)
ORDER BY
    (COUNTRY_ID, WEEK, REGION);

CREATE TABLE IF NOT EXISTS sales_distributed ON CLUSTER '{cluster}' (
    WEEK Date32,
    COUNTRY_ID Decimal(38, 9),
    REGION String,
    PRODUCT_ID Nullable(Decimal(38, 10)),
    UNITS Nullable(Float64),
    DOLLAR_VOLUME Nullable(Decimal(38, 10))
) ENGINE = Distributed(replicated, currentDatabase(), sales_local, rand());

