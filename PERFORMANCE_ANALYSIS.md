# 效能測試與分析指南

本文件整理此專案的壓測流程、指標收集方法與結果紀錄格式。

## 目標

- 驗證 Kafka -> ClickHouse 管線在高吞吐下是否穩定
- 找出瓶頸在 Producer、Kafka、ClickHouse 或查詢層
- 建立可重現的測試流程，讓不同配置可比較

## 建議測試前提

- 使用假資料模式：`./start_fake_producers.sh`
- 測試期間不要混入真實 API producer
- 每次測試固定時間窗（建議 10-30 分鐘）

## 測試矩陣（建議）

| 場景 | top_games 配置 | game_details 配置 | 目標 |
|---|---|---|---|
| Baseline | 0.2s / 200 | 0.2s / 200 | 驗證基本穩定性 |
| Medium | 0.1s / 500 | 0.1s / 500 | 觀察 lag 開始點 |
| High | 0.05s / 1000 | 0.1s / 1000 | 接近目前預設高壓值 |
| Extreme | 0.02s / 1000 | 0.05s / 1000 | 尋找系統極限 |

註：表中格式為 `SEND_INTERVAL / BATCH_SIZE`。

## 指標收集

### 1) ClickHouse 寫入速率

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

### 3) 查詢延遲

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
LIMIT 50;
```

### 4) 資源占用

```bash
docker stats --no-stream kafka clickhouse-server grafana
```

## 結果紀錄模板

| 日期 | 場景 | 持續時間 | 平均寫入速率 | 峰值 Lag | P95 查詢延遲 | CPU/Memory | 結論 |
|---|---|---|---|---|---|---|---|
| YYYY-MM-DD | Baseline | 20 min | N/A | N/A | N/A | N/A | N/A |
| YYYY-MM-DD | Medium | 20 min | N/A | N/A | N/A | N/A | N/A |
| YYYY-MM-DD | High | 20 min | N/A | N/A | N/A | N/A | N/A |

## 判讀建議

- Lag 持續上升：通常是 ClickHouse 消費/寫入追不上
- Lag 可回落但有尖峰：通常是瞬間突發流量或 flush 週期造成
- 查詢延遲高但寫入正常：優先看 SQL、排序鍵、索引與資料量
- CPU 高且 lag 高：可先調整 `kafka_num_consumers`、batch、flush 參數

## 常用調整方向

1. 增加 Kafka Engine consumer 數量
2. 調整 producer 的 `SEND_INTERVAL` / `BATCH_SIZE`
3. 調整 ClickHouse Kafka Engine 參數（poll/flush/block size）
4. 分離壓測查詢與觀察查詢，避免互相干擾

## 實測結果填寫版

把下面內容直接複製一份，填完就是一版測試紀錄。

### 測試資訊

| 欄位 | 值 |
|---|---|
| 測試日期 | YYYY-MM-DD |
| 測試時間區間 | HH:MM - HH:MM |
| 測試環境 | 本機 / VM / 其他 |
| Kafka 版本 | N/A |
| ClickHouse 版本 | N/A |
| Producer 模式 | fake / real / mixed |
| 測試級別 | Baseline / Medium / High / Extreme |

### 參數設定

| 元件 | 參數 | 值 |
|---|---|---|
| fake_top_games | SEND_INTERVAL | N/A |
| fake_top_games | BATCH_SIZE | N/A |
| fake_game_details | SEND_INTERVAL | N/A |
| fake_game_details | BATCH_SIZE | N/A |
| ClickHouse Kafka Engine | kafka_num_consumers | N/A |
| ClickHouse Kafka Engine | kafka_max_block_size | N/A |
| ClickHouse Kafka Engine | kafka_flush_interval_ms | N/A |

### 量測結果

| 指標 | 結果 |
|---|---|
| 平均寫入速率（rows/sec） | N/A |
| 峰值寫入速率（rows/sec） | N/A |
| 平均 Consumer Lag | N/A |
| 峰值 Consumer Lag | N/A |
| P95 查詢延遲（ms） | N/A |
| P99 查詢延遲（ms） | N/A |
| Kafka CPU / Memory | N/A |
| ClickHouse CPU / Memory | N/A |

### 結論

| 項目 | 內容 |
|---|---|
| 主要瓶頸 | N/A |
| 瓶頸證據 | N/A |
| 本次調整是否有效 | N/A |
| 下一步動作 | N/A |
