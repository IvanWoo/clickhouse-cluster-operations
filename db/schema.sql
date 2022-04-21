
--
-- Database schema
--

CREATE DATABASE test IF NOT EXISTS;

CREATE TABLE test.events_local
(
    `event_date` Date,
    `event_type` Int32,
    `article_id` Int32,
    `title` String
)
ENGINE = ReplicatedMergeTree('/clickhouse/{installation}/{cluster}/tables/test/events_local', '{replica}')
ORDER BY (event_type, article_id)
SETTINGS index_granularity = 8192;

CREATE TABLE test.sales_distributed
(
    `WEEK` Date32,
    `COUNTRY_ID` Decimal(38, 9),
    `REGION` String,
    `PRODUCT_ID` Nullable(Decimal(38, 10)),
    `UNITS` Nullable(Float64),
    `DOLLAR_VOLUME` Nullable(Decimal(38, 10))
)
ENGINE = Distributed('replicated', 'test', 'sales_local', rand());

CREATE TABLE test.sales_local
(
    `WEEK` Date32,
    `COUNTRY_ID` Decimal(38, 9),
    `REGION` String,
    `PRODUCT_ID` Nullable(Decimal(38, 10)),
    `UNITS` Nullable(Float64),
    `DOLLAR_VOLUME` Nullable(Decimal(38, 10))
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(WEEK)
ORDER BY (COUNTRY_ID, WEEK, REGION)
SETTINGS index_granularity = 8192;

CREATE TABLE test.schema_migrations
(
    `version` String,
    `ts` DateTime DEFAULT now(),
    `applied` UInt8 DEFAULT 1
)
ENGINE = ReplicatedReplacingMergeTree('/clickhouse/{installation}/{cluster}/tables/test/schema_migrations', '{replica}', ts)
PRIMARY KEY version
ORDER BY version
SETTINGS index_granularity = 8192;


--
-- Dbmate schema migrations
--

INSERT INTO schema_migrations (version) VALUES
    ('20220415224306'),
    ('20220415232010'),
    ('20220421153914');
