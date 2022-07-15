-- migrate:up
CREATE TABLE IF NOT EXISTS sales_distributed ON CLUSTER '{cluster}' (
    WEEK Date32,
    COUNTRY_ID UInt64,
    REGION String,
    PRODUCT_ID Nullable(UInt64),
    UNITS Nullable(Float64),
    DOLLAR_VOLUME Nullable(Decimal(38, 10))
) ENGINE = Distributed('{cluster}', currentDatabase(), sales_local, rand());

-- migrate:down
DROP TABLE IF EXISTS sales_distributed ON CLUSTER '{cluster}' SYNC;
