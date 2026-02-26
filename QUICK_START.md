# 快速啟動（學習與壓測）

這份指南用最短流程啟動專案，重點放在「假資料壓測 + 效能觀察」。

## 推薦流程（5 分鐘）

### 1. 初始化

```bash
./setup.sh
```

### 2. 啟動假資料產生器

```bash
./start_fake_producers.sh
```

### 3. 驗證資料流

```bash
# Kafka: 看 5 筆訊息
docker exec kafka kafka-console-consumer \
  --topic steam_top_games_topic \
  --bootstrap-server localhost:9092 \
  --max-messages 5

# ClickHouse: 看資料筆數
docker exec clickhouse-server clickhouse-client --query \
  "SELECT count() FROM steam_top_games"

docker exec clickhouse-server clickhouse-client --query \
  "SELECT count() FROM steam_game_details"
```

### 4. 觀察核心指標

```bash
# Consumer Lag
docker exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe \
  --group clickhouse_steam_top_games_consumer

# 容器資源
docker stats --no-stream kafka clickhouse-server grafana
```

### 5. 停止測試

```bash
./stop_producers.sh
```

## 可選：真實資料模式

如果你要驗證外部 API 整合，再改用：

```bash
./start_producers.sh
```

這模式吞吐量明顯較低，主要受外部 API 速率限制。

## 常用命令

```bash
# 重啟基礎設施
docker-compose restart

# 關閉基礎設施（保留 volume）
docker-compose down

# 完全清理（刪除 volume）
docker-compose down -v

# 重新建立 Kafka Engine 表 / Materialized View
./recreate_kafka_tables.sh
```

## 下一步文件

- [README.md](README.md)
- [SCRIPTS_GUIDE.md](SCRIPTS_GUIDE.md)
- [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md)
