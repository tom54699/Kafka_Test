#!/bin/bash
# 重建 ClickHouse Kafka Engine 表以應用新配置

set -e

echo "==========================================="
echo "重建 ClickHouse Kafka Engine 表"
echo "==========================================="

# 刪除舊的 Materialized Views 和 Kafka Engine 表
echo "1. 刪除舊的 Materialized Views..."
docker exec clickhouse-server clickhouse-client --query "DROP VIEW IF EXISTS steam_top_games_mv"
docker exec clickhouse-server clickhouse-client --query "DROP VIEW IF EXISTS steam_game_details_mv"
echo "✓ Materialized Views 已刪除"

echo ""
echo "2. 刪除舊的 Kafka Engine 表..."
docker exec clickhouse-server clickhouse-client --query "DROP TABLE IF EXISTS kafka_steam_top_games"
docker exec clickhouse-server clickhouse-client --query "DROP TABLE IF EXISTS kafka_steam_game_details"
echo "✓ Kafka Engine 表已刪除"

# 重新建立（保留 MergeTree 表，資料不會丟失）
echo ""
echo "3. 重新建立 Kafka Engine 表和 Materialized Views..."

# 建立 steam_top_games 的 Kafka Engine 表
docker exec clickhouse-server clickhouse-client --query "
CREATE TABLE kafka_steam_top_games (
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
    kafka_group_name = 'clickhouse_steam_top_games_consumer_v2',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 3,
    kafka_flush_interval_ms = 1000,
    kafka_poll_timeout_ms = 1000,
    kafka_max_block_size = 100
"

# 建立 steam_top_games 的 Materialized View
docker exec clickhouse-server clickhouse-client --query "
CREATE MATERIALIZED VIEW steam_top_games_mv TO steam_top_games AS
SELECT
    game_id,
    game_name,
    current_players,
    peak_today,
    rank,
    fetch_time
FROM kafka_steam_top_games
"

# 建立 steam_game_details 的 Kafka Engine 表
docker exec clickhouse-server clickhouse-client --query "
CREATE TABLE kafka_steam_game_details (
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
    kafka_group_name = 'clickhouse_steam_game_details_consumer_v2',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 3,
    kafka_flush_interval_ms = 1000,
    kafka_poll_timeout_ms = 1000,
    kafka_max_block_size = 100
"

# 建立 steam_game_details 的 Materialized View
docker exec clickhouse-server clickhouse-client --query "
CREATE MATERIALIZED VIEW steam_game_details_mv TO steam_game_details AS
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
FROM kafka_steam_game_details
"

echo "✓ Kafka Engine 表和 Materialized Views 已重新建立"

# 驗證
echo ""
echo "4. 驗證配置..."
docker exec clickhouse-server clickhouse-client --query "SHOW TABLES"

echo ""
echo "==========================================="
echo "✓ 完成！新配置已應用"
echo "==========================================="
echo ""
echo "最佳化說明："
echo "  - kafka_num_consumers: 1 → 3 (增加並行消費者)"
echo "  - kafka_flush_interval_ms: 7500 → 1000 (加快寫入速度)"
echo "  - kafka_poll_timeout_ms: 預設 → 1000 (減少輪詢等待)"
echo "  - kafka_max_block_size: 預設 → 100 (適合小批次即時寫入)"
echo ""
echo "注意：使用了新的 consumer group (_v2)，會從最新的 offset 開始消費"
echo "如需從頭消費，請重置 Kafka consumer group offset"
echo ""
