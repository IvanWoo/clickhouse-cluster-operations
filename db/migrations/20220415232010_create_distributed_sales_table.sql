-- migrate:up
CREATE TABLE IF NOT EXISTS sales_distributed ON CLUSTER '{cluster}' (
    WEEK Date32,
    COUNTRY_ID Decimal(38, 9),
    REGION String,
    PRODUCT_ID Nullable(Decimal(38, 10)),
    UNITS Nullable(Float64),
    DOLLAR_VOLUME Nullable(Decimal(38, 10))
) ENGINE = Distributed(replicated, test, sales_local, rand());

-- migrate:down
DROP TABLE IF EXISTS sales_distributed ON CLUSTER '{cluster}';
