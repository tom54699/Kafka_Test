# Kafka + ClickHouse 學習與效能測試專案

本專案是用來練習 Kafka / ClickHouse / Grafana 的本地資料管線，核心目標是**壓力測試與效能分析**。

目前資料表與 Topic 名稱保留 `steam_*` 命名（歷史原因），但專案本質不是 Steam 業務專案。

## 專案定位

- 學習 Kafka Topic / Consumer / Lag 的行為
- 學習 ClickHouse Kafka Engine + Materialized View 寫入路徑
- 用假資料生成器進行高吞吐壓測，分析瓶頸
- 用 Grafana 做即時監控與效能觀察

## 資料流

```text
Fake Producers (高頻) / Real Producers (低頻)
  -> Kafka Topics
  -> ClickHouse Kafka Engine Tables
  -> Materialized Views
  -> MergeTree Tables
  -> Grafana
```

## 兩種模式

### 1) 假資料模式（預設，建議）

適用情境：壓力測試、效能調優、學習資料流行為

- `fake_steam_top_games_producer.py`
- `fake_steam_game_details_producer.py`

目前預設配置（程式碼設定值）：

- `steam_top_games`: 約 `20,000 records/sec`
- `steam_game_details`: 約 `10,000 records/sec`
- 總目標吞吐：`30,000 records/sec`

### 2) 真實資料模式（次要）

適用情境：驗證外部 API 整合流程

- `steam_top_games_producer.py`
- `steam_game_details_producer.py`

此模式吞吐量低很多，主要受外部 API 限制。

## 快速開始（建議流程）

### 1. 初始化基礎設施

```bash
./setup.sh
```

這會建立 Docker 服務、Kafka Topics、ClickHouse schema 與必要目錄。

### 2. 啟動假資料壓測

```bash
./start_fake_producers.sh
```

### 3. 驗證資料是否進來

```bash
docker exec clickhouse-server clickhouse-client --query \
  "SELECT count() FROM steam_top_games"

docker exec clickhouse-server clickhouse-client --query \
  "SELECT count() FROM steam_game_details"
```

### 4. 停止測試

```bash
./stop_producers.sh
```

## 效能分析重點

壓測不是只看「有資料」，重點是以下四類指標。

### 1) 吞吐量（Ingestion Throughput）

```sql
SELECT
    toStartOfMinute(fetch_time) AS minute,
    count() AS rows
FROM steam_top_games
WHERE fetch_time >= now() - INTERVAL 30 MINUTE
GROUP BY minute
ORDER BY minute DESC;
```

### 2) Kafka Consumer Lag

```bash
docker exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe \
  --group clickhouse_steam_top_games_consumer
```

### 3) 查詢延遲（Query Latency）

```sql
SELECT
    query_duration_ms,
    read_rows,
    memory_usage,
    event_time
FROM system.query_log
WHERE type = 'QueryFinish'
  AND event_time >= now() - INTERVAL 15 MINUTE
ORDER BY event_time DESC
LIMIT 20;
```

### 4) 儲存成長（Storage Growth）

```sql
SELECT
    table,
    sum(rows) AS rows,
    formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE active
  AND database = 'default'
GROUP BY table
ORDER BY rows DESC;
```

## 壓測結果文件

請直接看這份：

- [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md)

內含：

- 壓測流程
- 指標收集 SQL/命令
- 結果表格模板
- 瓶頸判讀方式

## 文件導覽

- [DOCS_INDEX.md](DOCS_INDEX.md): 全部文件索引
- [SCRIPTS_GUIDE.md](SCRIPTS_GUIDE.md): 所有腳本與使用方式
- [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md): 架構與設計說明
- [HIGH_FREQUENCY_CONFIG.md](HIGH_FREQUENCY_CONFIG.md): 高頻配置策略
- [KAFKA_UI_GUIDE.md](KAFKA_UI_GUIDE.md): Kafka UI 監控
- [GRAFANA_CLICKHOUSE_STEP_BY_STEP.md](GRAFANA_CLICKHOUSE_STEP_BY_STEP.md): Grafana 設定

## 注意事項

- `steam_*` 命名是示範 schema，代表「事件資料模型」，不代表實際商業域。
- 高吞吐測試請優先用假資料，避免外部 API rate limit 干擾分析。
- 如果要比較不同配置效果，請一次只改一個變數（例如 batch size 或 consumer 數）。
