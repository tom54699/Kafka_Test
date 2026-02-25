-- ================================================================
-- Steam 數據管線 ClickHouse Schema
-- ================================================================
-- 專案說明：建立兩個數據管線來追蹤 Steam 熱門遊戲統計與遊戲詳細資訊
-- 架構：Kafka Engine Table -> Materialized View -> MergeTree Table
-- ================================================================

-- ================================================================
-- Pipeline 1: Steam 熱門遊戲玩家統計
-- ================================================================

-- 1.1 建立 Kafka Engine 表 (消費 steam_top_games_topic)
CREATE TABLE IF NOT EXISTS kafka_steam_top_games (
    game_id UInt32,
    game_name String,
    current_players UInt32,
    peak_today UInt32,
    rank UInt16,
    fetch_time DateTime
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'steam_top_games_topic',
    kafka_group_name = 'clickhouse_steam_top_games_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 3,
    kafka_flush_interval_ms = 1000,
    kafka_poll_timeout_ms = 1000,
    kafka_max_block_size = 100;

-- 1.2 建立 MergeTree 實體表 (儲存熱門遊戲玩家統計)
CREATE TABLE IF NOT EXISTS steam_top_games (
    game_id UInt32,
    game_name String,
    current_players UInt32,
    peak_today UInt32,
    rank UInt16,
    fetch_time DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(fetch_time)
ORDER BY (game_id, fetch_time)
TTL fetch_time + INTERVAL 90 DAY;  -- 保留 90 天資料

-- 1.3 建立 Materialized View (自動從 Kafka 寫入 MergeTree)
CREATE MATERIALIZED VIEW IF NOT EXISTS steam_top_games_mv TO steam_top_games AS
SELECT
    game_id,
    game_name,
    current_players,
    peak_today,
    rank,
    fetch_time
FROM kafka_steam_top_games;

-- ================================================================
-- Pipeline 2: Steam 遊戲詳細資訊
-- ================================================================

-- 2.1 建立 Kafka Engine 表 (消費 steam_game_details_topic)
CREATE TABLE IF NOT EXISTS kafka_steam_game_details (
    game_id UInt32,
    game_name String,
    short_description String,
    release_date String,
    developers Array(String),
    publishers Array(String),
    genres Array(String),
    original_price Float32,
    discount_percent UInt8,
    final_price Float32,
    positive_reviews UInt32,
    negative_reviews UInt32,
    total_reviews UInt32,
    review_score Float32,
    fetch_time DateTime
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'steam_game_details_topic',
    kafka_group_name = 'clickhouse_steam_game_details_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 3,
    kafka_flush_interval_ms = 1000,
    kafka_poll_timeout_ms = 1000,
    kafka_max_block_size = 100;

-- 2.2 建立 MergeTree 實體表 (儲存遊戲詳細資訊)
CREATE TABLE IF NOT EXISTS steam_game_details (
    game_id UInt32,
    game_name String,
    short_description String,
    release_date String,
    developers Array(String),
    publishers Array(String),
    genres Array(String),
    original_price Float32,
    discount_percent UInt8,
    final_price Float32,
    positive_reviews UInt32,
    negative_reviews UInt32,
    total_reviews UInt32,
    review_score Float32,
    fetch_time DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(fetch_time)
ORDER BY (game_id, fetch_time)
TTL fetch_time + INTERVAL 180 DAY;  -- 保留 180 天資料

-- 2.3 建立 Materialized View (自動從 Kafka 寫入 MergeTree)
CREATE MATERIALIZED VIEW IF NOT EXISTS steam_game_details_mv TO steam_game_details AS
SELECT
    game_id,
    game_name,
    short_description,
    release_date,
    developers,
    publishers,
    genres,
    original_price,
    discount_percent,
    final_price,
    positive_reviews,
    negative_reviews,
    total_reviews,
    review_score,
    fetch_time
FROM kafka_steam_game_details;

-- ================================================================
-- 實用查詢範例
-- ================================================================

-- 查詢最新的熱門遊戲排行
-- SELECT game_name, current_players, rank, fetch_time
-- FROM steam_top_games
-- WHERE fetch_time = (SELECT max(fetch_time) FROM steam_top_games)
-- ORDER BY rank ASC
-- LIMIT 20;

-- 查詢特定遊戲的玩家數趨勢
-- SELECT
--     toDateTime(toStartOfInterval(fetch_time, INTERVAL 1 HOUR)) as hour,
--     game_name,
--     avg(current_players) as avg_players,
--     max(current_players) as max_players
-- FROM steam_top_games
-- WHERE game_id = 730 AND fetch_time >= now() - INTERVAL 24 HOUR
-- GROUP BY hour, game_name
-- ORDER BY hour DESC;

-- 查詢目前最熱門且有折扣的遊戲
-- SELECT
--     g.game_name,
--     g.current_players,
--     d.original_price,
--     d.discount_percent,
--     d.final_price,
--     d.review_score
-- FROM steam_top_games g
-- INNER JOIN steam_game_details d ON g.game_id = d.game_id
-- WHERE g.fetch_time >= now() - INTERVAL 1 HOUR
--   AND d.fetch_time >= now() - INTERVAL 1 DAY
--   AND d.discount_percent > 0
-- ORDER BY g.current_players DESC
-- LIMIT 20;
