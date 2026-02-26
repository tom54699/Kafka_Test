# 專案架構概覽

## 專案定位

這是一個用於學習與效能測試的資料管線專案，核心問題是：

- 高頻事件進來時，Kafka 能否穩定承接？
- ClickHouse 是否能持續消費並寫入？
- 查詢延遲會如何變化？

備註：資料表/Topic 目前沿用 `steam_*` 命名，僅為示範模型，不代表特定業務域。

## 架構分層

```text
Data Generators (Fake / Real)
  -> Kafka Topics
  -> ClickHouse Kafka Engine Tables
  -> Materialized Views
  -> MergeTree Tables
  -> Grafana Dashboards
```

## 各層角色

### 1. Data Generators

- `fake_steam_top_games_producer.py`
- `fake_steam_game_details_producer.py`
- `steam_top_games_producer.py`（外部 API 模式）
- `steam_game_details_producer.py`（外部 API 模式）

建議壓測時優先使用 fake producers，減少外部 API 速率限制干擾。

### 2. Kafka

- Topic: `steam_top_games_topic`
- Topic: `steam_game_details_topic`

用途：吸收突發流量、解耦 producer 與 ClickHouse。

### 3. ClickHouse

- `kafka_steam_*`: Kafka Engine 表，負責拉取 Topic
- `steam_*_mv`: Materialized View，負責轉換/搬運
- `steam_*`: MergeTree 實體表，負責查詢與儲存

### 4. Grafana

用途：觀察吞吐、趨勢與查詢結果，快速識別 lag 或寫入異常。

## 主要腳本

- `setup.sh`: 初始化服務、Topic、Schema
- `start_fake_producers.sh`: 啟動高頻假資料產生器
- `start_producers.sh`: 啟動低頻真實資料 producer
- `stop_producers.sh`: 停止所有 producers
- `recreate_kafka_tables.sh`: 重建 Kafka Engine 與 MV

## 建議效能分析流程

1. `./setup.sh`
2. `./start_fake_producers.sh`
3. 收集吞吐量、lag、查詢延遲、資源占用
4. 調整一個參數後重測（consumer、batch、interval）
5. 產出對照表與結論

詳細指標和模板請看 [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md)。
