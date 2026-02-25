#!/bin/bash
# 重建 ClickHouse Kafka Engine 表以应用新配置

set -e

echo "==========================================="
echo "重建 ClickHouse Kafka Engine 表"
echo "==========================================="

# 删除旧的 Materialized Views 和 Kafka Engine 表
echo "1. 删除旧的 Materialized Views..."
docker exec clickhouse-server clickhouse-client --query "DROP VIEW IF EXISTS steam_top_games_mv"
docker exec clickhouse-server clickhouse-client --query "DROP VIEW IF EXISTS steam_game_details_mv"
echo "✓ Materialized Views 已删除"

echo ""
echo "2. 删除旧的 Kafka Engine 表..."
docker exec clickhouse-server clickhouse-client --query "DROP TABLE IF EXISTS kafka_steam_top_games"
docker exec clickhouse-server clickhouse-client --query "DROP TABLE IF EXISTS kafka_steam_game_details"
echo "✓ Kafka Engine 表已删除"

# 重新创建（保留 MergeTree 表，数据不会丢失）
echo ""
echo "3. 重新创建 Kafka Engine 表和 Materialized Views..."

# 创建 steam_top_games 的 Kafka Engine 表
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

# 创建 steam_top_games 的 Materialized View
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

# 创建 steam_game_details 的 Kafka Engine 表
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

# 创建 steam_game_details 的 Materialized View
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

echo "✓ Kafka Engine 表和 Materialized Views 已重新创建"

# 验证
echo ""
echo "4. 验证配置..."
docker exec clickhouse-server clickhouse-client --query "SHOW TABLES"

echo ""
echo "==========================================="
echo "✓ 完成！新配置已应用"
echo "==========================================="
echo ""
echo "优化说明："
echo "  - kafka_num_consumers: 1 → 3 (增加并行消费者)"
echo "  - kafka_flush_interval_ms: 7500 → 1000 (加快写入速度)"
echo "  - kafka_poll_timeout_ms: 默认 → 1000 (减少轮询等待)"
echo "  - kafka_max_block_size: 默认 → 100 (适合小批量实时写入)"
echo ""
echo "注意：使用了新的 consumer group (_v2)，会从最新的 offset 开始消费"
echo "如需从头消费，请重置 Kafka consumer group offset"
echo ""
