-- migrate:up
CREATE TABLE IF NOT EXISTS products_local ON CLUSTER '{cluster}' (
    PRODUCT_ID Decimal(38, 10),
    PRODUCT_NAME String
) ENGINE = ReplicatedMergeTree('/clickhouse/{installation}/{cluster}/tables/{shard}/{database}/{table}', '{replica}')
ORDER BY
    (PRODUCT_ID);

-- migrate:down
DROP TABLE IF EXISTS products_local ON CLUSTER '{cluster}' SYNC;
