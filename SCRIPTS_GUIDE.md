# 指令碼使用指南

本專案主軸是學習 Kafka + ClickHouse 資料管線，並用高頻假資料進行效能測試。

## 指令碼總覽

| 指令碼 | 作用 | 典型時機 |
|---|---|---|
| `setup.sh` | 初始化整個環境（Docker、Topic、Schema） | 第一次啟動 |
| `start_fake_producers.sh` | 啟動高頻假資料產生器 | 壓測、調優 |
| `start_producers.sh` | 啟動真實資料 producer | 驗證 API 整合 |
| `stop_producers.sh` | 停止所有 producer | 測試結束或切模式 |
| `recreate_kafka_tables.sh` | 重建 ClickHouse Kafka Engine/MV | 調整 Kafka 消費配置後 |

## 1) `setup.sh`

用途：一次完成初始化。

會做的事：
- 啟動 Kafka / ClickHouse / Grafana
- 建立 Kafka Topics
- 套用 `clickhouse_schema.sql`
- 安裝 Python 套件與必要目錄

```bash
./setup.sh
```

## 2) `start_fake_producers.sh`（建議主流程）

用途：啟動壓測用資料流。

啟動項目：
- `fake_steam_top_games_producer.py`
- `fake_steam_game_details_producer.py`

目前程式配置吞吐量：
- `steam_top_games`: 約 20,000 records/sec
- `steam_game_details`: 約 10,000 records/sec
- 總量：約 30,000 records/sec

```bash
./start_fake_producers.sh
```

常用觀察：

```bash
tail -f logs/fake_top_games.log
tail -f logs/fake_game_details.log
```

## 3) `start_producers.sh`（次要流程）

用途：驗證真實 API 整合鏈路。

注意：吞吐量會低很多，不適合用來測系統極限。

```bash
./start_producers.sh
```

## 4) `stop_producers.sh`

用途：停止真實與假資料 producer。

```bash
./stop_producers.sh
```

## 5) `recreate_kafka_tables.sh`

用途：重建 Kafka Engine 表與 Materialized View。

使用情境：
- 調整了 `kafka_num_consumers`
- 需要重置消費流程
- Kafka Engine 異常要重建

```bash
./recreate_kafka_tables.sh
```

## 建議工作流

### 首次上手

```bash
./setup.sh
./start_fake_producers.sh
```

### 壓測與調優

```bash
./stop_producers.sh
./start_fake_producers.sh
# 觀察 lag、寫入速率、查詢延遲
```

### 切到真實資料驗證

```bash
./stop_producers.sh
./start_producers.sh
```

## 效能監控命令

```bash
# Consumer Lag
docker exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe \
  --group clickhouse_steam_top_games_consumer

# ClickHouse 資料量
docker exec clickhouse-server clickhouse-client --query "
SELECT
    table,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE active AND database = 'default'
GROUP BY table
ORDER BY sum(rows) DESC
"

# 容器資源
docker stats --no-stream kafka clickhouse-server grafana
```

## 常見問題

### producer 啟不來

```bash
docker ps | rg 'kafka|clickhouse|grafana'
pip install -r requirements.txt
```

### ClickHouse 沒資料

```bash
docker exec clickhouse-server clickhouse-client --query \
  "SELECT * FROM kafka_steam_top_games LIMIT 5"
```

### 想重置再測一次

```bash
./stop_producers.sh
docker-compose down -v
./setup.sh
```

## 相關文件

- [QUICK_START.md](QUICK_START.md)
- [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md)
- [HIGH_FREQUENCY_CONFIG.md](HIGH_FREQUENCY_CONFIG.md)
