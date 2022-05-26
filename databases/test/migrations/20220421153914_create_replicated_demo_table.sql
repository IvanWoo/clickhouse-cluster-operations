-- migrate:up
CREATE TABLE IF NOT EXISTS events_local on cluster '{cluster}' (
    event_date  Date,
    event_type  Int32,
    article_id  Int32,
    title       String
) engine=ReplicatedMergeTree('/clickhouse/{installation}/{cluster}/tables/{database}/{table}', '{replica}')
ORDER BY (event_type, article_id);

-- migrate:down
DROP TABLE IF EXISTS events_local ON CLUSTER '{cluster}' SYNC;
