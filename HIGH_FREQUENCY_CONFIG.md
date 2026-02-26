# 高頻配置與壓測策略

本文件說明如何調整假資料產生器吞吐量，並用一致流程做效能比較。

## 先確認目前預設

目前 `fake` producers 的程式設定值：

- `fake_steam_top_games_producer.py`: `SEND_INTERVAL=0.05`, `BATCH_SIZE=1000`（約 20,000 records/sec）
- `fake_steam_game_details_producer.py`: `SEND_INTERVAL=0.1`, `BATCH_SIZE=1000`（約 10,000 records/sec）

總目標吞吐：約 30,000 records/sec。

## 建議壓測分級

| 級別 | top_games | game_details | 總目標吞吐 | 用途 |
|---|---|---|---|---|
| L1 | 0.2s / 200 | 0.2s / 200 | 約 2,000/sec | 基線測試 |
| L2 | 0.1s / 500 | 0.1s / 500 | 約 10,000/sec | 日常調優 |
| L3 | 0.05s / 1000 | 0.1s / 1000 | 約 30,000/sec | 高壓測試 |
| L4 | 0.02s / 1000 | 0.05s / 1000 | 約 70,000/sec | 找極限 |

格式：`SEND_INTERVAL / BATCH_SIZE`。

## 如何調整

分別修改以下檔案：

- `fake_steam_top_games_producer.py`
- `fake_steam_game_details_producer.py`

範例：

```python
SEND_INTERVAL = 0.1
BATCH_SIZE = 500
```

修改後重啟：

```bash
./stop_producers.sh
./start_fake_producers.sh
```

## 壓測建議流程

1. 選一個級別，固定跑 20 分鐘。
2. 記錄寫入速率、lag、查詢延遲、資源占用。
3. 只改一個變數再測（避免變因混雜）。
4. 對照結果，找出瓶頸位置。

完整模板見 [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md)。

## 核心觀察指標

### Kafka lag

```bash
docker exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe \
  --group clickhouse_steam_top_games_consumer
```

### ClickHouse 寫入速率

```sql
SELECT
    toStartOfMinute(fetch_time) AS minute,
    count() AS rows
FROM steam_top_games
WHERE fetch_time >= now() - INTERVAL 30 MINUTE
GROUP BY minute
ORDER BY minute DESC;
```

### 查詢延遲

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

### 系統資源

```bash
docker stats --no-stream kafka clickhouse-server grafana
```

## 常見瓶頸判讀

- Lag 持續上升：ClickHouse 消費/寫入能力不足
- Lag 偶發尖峰：瞬時流量突增或 flush 週期影響
- 查詢慢但 lag 穩定：多半是 SQL 或資料模型問題
- CPU 長時間滿載：優先檢查 consumer 數與 batch 參數
