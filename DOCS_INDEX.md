# 文件索引

本專案主軸是「Kafka + ClickHouse 學習與效能測試」。

## 建議先讀

| 文件 | 說明 | 何時看 |
|---|---|---|
| [README.md](README.md) | 專案定位、啟動方式、核心指標 | 第一次進專案 |
| [SCRIPTS_GUIDE.md](SCRIPTS_GUIDE.md) | 所有腳本功能與操作 | 要跑流程前 |
| [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md) | 壓測方法、指標收集、結果模板 | 開始效能測試前 |

## 架構與原理

| 文件 | 說明 |
|---|---|
| [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) | 架構設計與資料流分層 |
| [KAFKA_CLICKHOUSE_LEARNING_GUIDE.md](KAFKA_CLICKHOUSE_LEARNING_GUIDE.md) | Kafka + ClickHouse 原理與實作 |

## 配置與操作

| 文件 | 說明 |
|---|---|
| [HIGH_FREQUENCY_CONFIG.md](HIGH_FREQUENCY_CONFIG.md) | 高頻資料配置策略 |
| [KAFKA_UI_GUIDE.md](KAFKA_UI_GUIDE.md) | Kafka UI 觀察訊息與 Consumer |
| [GRAFANA_CLICKHOUSE_STEP_BY_STEP.md](GRAFANA_CLICKHOUSE_STEP_BY_STEP.md) | Grafana 設定步驟 |
| [ENV_SETUP_GUIDE.md](ENV_SETUP_GUIDE.md) | 環境變數與設定細節 |
| [QUICK_START.md](QUICK_START.md) | 快速啟動命令清單 |

## 依場景閱讀

### 場景 A: 想快速壓測
1. [README.md](README.md)
2. [SCRIPTS_GUIDE.md](SCRIPTS_GUIDE.md)
3. [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md)

### 場景 B: 想理解整體架構
1. [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md)
2. [KAFKA_CLICKHOUSE_LEARNING_GUIDE.md](KAFKA_CLICKHOUSE_LEARNING_GUIDE.md)

### 場景 C: 想優化效能
1. [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md)
2. [HIGH_FREQUENCY_CONFIG.md](HIGH_FREQUENCY_CONFIG.md)
3. [KAFKA_UI_GUIDE.md](KAFKA_UI_GUIDE.md)
