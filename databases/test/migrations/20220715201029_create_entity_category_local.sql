-- migrate:up
CREATE TABLE IF NOT EXISTS entity_category_local ON CLUSTER '{cluster}' (
    PRODUCT_ID UInt64,
    CATEGORY String
) ENGINE = ReplicatedMergeTree('/clickhouse/{installation}/{cluster}/tables/{shard}/{database}/{table}', '{replica}')
ORDER BY
    (PRODUCT_ID);

-- migrate:down
DROP TABLE IF EXISTS entity_category_local ON CLUSTER '{cluster}' SYNC;
