-- migrate:up
CREATE TABLE IF NOT EXISTS products_distributed ON CLUSTER '{cluster}' (
    PRODUCT_ID UInt64,
    PRODUCT_NAME String
) ENGINE = Distributed('{cluster}', currentDatabase(), products_local, rand());

-- migrate:down
DROP TABLE IF EXISTS products_distributed ON CLUSTER '{cluster}' SYNC;
