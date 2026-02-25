# 指令碼使用指南

本專案包含多個 Shell 指令碼，用於簡化 Kafka + ClickHouse 資料管線的部署和管理。

## 📋 指令碼總覽

| 指令碼名稱 | 用途 | 使用場景 |
|---------|------|---------|
| `setup.sh` | 一次性初始化設定 | 首次部署專案 |
| `start_producers.sh` | 啟動真實資料 Producers | 使用 Steam API 獲取真實資料 |
| `start_fake_producers.sh` | 啟動假資料生成器 | 壓力測試、開發除錯 |
| `stop_producers.sh` | 停止所有 Producers | 停止資料生成 |
| `recreate_kafka_tables.sh` | 重建 Kafka Engine 表 | 更新配置或重置消費者 |

---

## 🚀 指令碼詳細說明

### 1. setup.sh - 初始化設定指令碼

**用途**: 一次性完成專案的所有初始化工作

**執行內容**:
- ✅ 檢查 Docker 和 Docker Compose 是否安裝
- ✅ 啟動基礎設施（Kafka, ClickHouse, Grafana）
- ✅ 建立 Kafka Topics
- ✅ 執行 ClickHouse Schema（建立表和 Materialized Views）
- ✅ 安裝 Python 依賴包
- ✅ 建立日誌目錄
- ✅ 設定指令碼執行許可權

**使用方法**:
```bash
./setup.sh
```

**預期時間**: 約 30-60 秒

**注意事項**:
- 只需在首次部署時執行一次
- 如果 Docker 服務未啟動，會報錯並終止
- 如果已有同名的 Topics 或表，會跳過建立

---

### 2. start_producers.sh - 啟動真實資料 Producers

**用途**: 啟動兩個 Python Producers，從 Steam API 獲取真實遊戲資料

**啟動的服務**:
1. `steam_top_games_producer.py` - 每 10 分鐘抓取熱門遊戲統計
2. `steam_game_details_producer.py` - 每 1 小時抓取遊戲詳細資訊

**資料流向**:
```
Steam API → Producers → Kafka Topics → ClickHouse
```

**使用方法**:
```bash
./start_producers.sh
```

**資料量**:
- 熱門遊戲: ~100 條/10分鐘 = 10 條/分鐘
- 遊戲詳情: ~100 條/小時 = 1.67 條/分鐘

**日誌檢視**:
```bash
tail -f logs/top_games.log
tail -f logs/game_details.log
```

**停止方法**:
```bash
./stop_producers.sh
```

---

### 3. start_fake_producers.sh - 啟動假資料生成器

**用途**: 啟動高頻假資料生成器，用於壓力測試和效能調優

**啟動的服務**:
1. `fake_steam_top_games_producer.py` - 高頻生成熱門遊戲資料
2. `fake_steam_game_details_producer.py` - 高頻生成遊戲詳情資料

**資料流向**:
```
假資料生成器 → Kafka Topics → ClickHouse
（使用與真實資料相同的 Topics 和 Schema）
```

**使用方法**:
```bash
./start_fake_producers.sh
```

**當前配置的吞吐量**:
- steam_top_games: 20,000 條/秒
- steam_game_details: 10,000 條/秒
- **總計: 30,000 條/秒**

**效能對比**:

| 模式 | 吞吐量 | 適用場景 |
|-----|--------|---------|
| 真實資料 | ~12 條/分鐘 | 生產環境、真實資料分析 |
| 假資料 | 30,000 條/秒 | 壓力測試、效能調優 |

**調整吞吐量**:
編輯 `fake_steam_top_games_producer.py` 和 `fake_steam_game_details_producer.py`:
```python
SEND_INTERVAL = 0.05  # 傳送間隔（秒）
BATCH_SIZE = 1000     # 每批數量
```

**資料增長預估**（當前配置）:
- 每分鐘: 1,800,000 條
- 每小時: 108,000,000 條（1.08 億）
- 每天: 2,592,000,000 條（25.92 億）

**日誌檢視**:
```bash
tail -f logs/fake_top_games.log
tail -f logs/fake_game_details.log
```

**即時監控資料增長**:
```bash
watch -n 1 'docker exec clickhouse-server clickhouse-client --query "SELECT count() FROM steam_top_games"'
```

**停止方法**:
```bash
./stop_producers.sh
```

---

### 4. stop_producers.sh - 停止所有 Producers

**用途**: 停止所有正在執行的 Producers（真實 + 假資料）

**執行內容**:
- 查詢所有 producer 程序
- 優雅停止（SIGTERM）
- 如果無法停止，強制終止（SIGKILL）
- 驗證所有程序已停止

**使用方法**:
```bash
./stop_producers.sh
```

**停止的程序**:
- steam_top_games_producer.py
- steam_game_details_producer.py
- fake_steam_top_games_producer.py
- fake_steam_game_details_producer.py

---

### 5. recreate_kafka_tables.sh - 重建 Kafka Engine 表

**用途**: 刪除並重新建立 ClickHouse 的 Kafka Engine 表和 Materialized Views

**使用場景**:
- 更新 Kafka 消費者配置（如增加 consumer 數量）
- 重置消費者 offset
- 修復損壞的 Kafka Engine 表

**執行內容**:
1. 刪除 Materialized Views
2. 刪除 Kafka Engine 表
3. 重新建立 Kafka Engine 表（使用最佳化配置）
4. 重新建立 Materialized Views

**最佳化配置**:
```
kafka_num_consumers: 3           # 並行消費者數量
kafka_flush_interval_ms: 1000    # 重新整理間隔 1 秒
kafka_poll_timeout_ms: 1000      # 輪詢超時 1 秒
kafka_max_block_size: 100        # 批次大小
```

**使用方法**:
```bash
./recreate_kafka_tables.sh
```

**注意事項**:
- ⚠️ **不會**刪除 MergeTree 表（實際資料不會丟失）
- ⚠️ **會**建立新的 Consumer Group（_v2）
- ⚠️ 新 Consumer Group 從最新 offset 開始消費

---

## 🔄 常見工作流

### 場景 1: 首次部署專案

```bash
# 1. 初始化專案
./setup.sh

# 2. 啟動真實資料採集
./start_producers.sh

# 3. 檢視日誌確認執行正常
tail -f logs/top_games.log

# 4. 訪問 Grafana 檢視資料
# http://localhost:3000
```

### 場景 2: 壓力測試

```bash
# 1. 停止真實資料（如果正在執行）
./stop_producers.sh

# 2. 啟動假資料生成器
./start_fake_producers.sh

# 3. 即時監控資料增長
watch -n 1 'docker exec clickhouse-server clickhouse-client --query "SELECT count() FROM steam_top_games"'

# 4. 監控資源使用
watch -n 1 'docker stats --no-stream kafka clickhouse-server'

# 5. 測試完成後停止
./stop_producers.sh
```

### 場景 3: 更新 Kafka 消費配置

```bash
# 1. 停止所有 Producers
./stop_producers.sh

# 2. 重建 Kafka Engine 表（應用新配置）
./recreate_kafka_tables.sh

# 3. 重新啟動 Producers
./start_fake_producers.sh  # 或 ./start_producers.sh
```

### 場景 4: 清理並重新開始

```bash
# 1. 停止 Producers
./stop_producers.sh

# 2. 停止基礎設施
docker-compose down -v

# 3. 重新初始化
./setup.sh

# 4. 啟動資料採集
./start_producers.sh
```

---

## 📊 效能監控命令

### 檢視 ClickHouse 資料量
```bash
docker exec clickhouse-server clickhouse-client --query "
SELECT
    table,
    formatReadableQuantity(sum(rows)) as rows,
    formatReadableSize(sum(bytes)) as size
FROM system.parts
WHERE active AND database = 'default'
GROUP BY table
"
```

### 檢視 Kafka Consumer Lag
```bash
docker exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe \
  --group clickhouse_steam_top_games_consumer_v2
```

### 檢視 Docker 容器資源使用
```bash
docker stats --no-stream kafka clickhouse-server grafana
```

### 檢視正在執行的 Producers
```bash
ps aux | grep producer.py | grep -v grep
```

---

## ⚙️ 指令碼配置引數

### 假資料生成器引數

在 `fake_steam_top_games_producer.py` 中:
```python
SEND_INTERVAL = 0.05  # 每 0.05 秒傳送一批
BATCH_SIZE = 1000     # 每批 1000 條
```

在 `fake_steam_game_details_producer.py` 中:
```python
SEND_INTERVAL = 0.1   # 每 0.1 秒傳送一批
BATCH_SIZE = 1000     # 每批 1000 條
```

**吞吐量方案**:

| 方案 | INTERVAL | BATCH_SIZE | 吞吐量 |
|-----|----------|------------|--------|
| 輕量 | 1 秒 | 50 | 50 條/秒 |
| 中等 | 0.2 秒 | 200 | 1,000 條/秒 |
| 高壓 | 0.1 秒 | 500 | 5,000 條/秒 |
| 極限 | 0.05 秒 | 1000 | 20,000 條/秒 |

---

## 🐛 故障排查

### Producer 無法啟動
```bash
# 檢查 Kafka 是否執行
docker ps | grep kafka

# 檢查 Kafka 連線
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092

# 檢視 Producer 日誌
tail -100 logs/top_games.log
```

### ClickHouse 不消費資料
```bash
# 檢查 Kafka Engine 表
docker exec clickhouse-server clickhouse-client --query "SELECT * FROM kafka_steam_top_games LIMIT 1"

# 檢查消費者狀態
docker exec clickhouse-server clickhouse-client --query "SELECT * FROM system.kafka_consumers FORMAT Vertical"

# 重建 Kafka 表
./recreate_kafka_tables.sh
```

### 指令碼許可權問題
```bash
# 新增執行許可權
chmod +x *.sh
```

---

## 📝 最佳實踐

1. **首次部署**: 先執行 `setup.sh`，確保所有基礎設施就緒
2. **開發除錯**: 使用假資料生成器，調整吞吐量到合適的值
3. **生產環境**: 使用真實資料 Producers，監控 Steam API rate limit
4. **效能測試**: 逐步提升假資料吞吐量，觀察系統瓶頸
5. **定期清理**: 根據 TTL 設定，定期清理歷史資料

---

## 🔗 相關文件

- [README.md](README.md) - 專案總覽
- [QUICK_START.md](QUICK_START.md) - 快速入門
- [HIGH_FREQUENCY_CONFIG.md](HIGH_FREQUENCY_CONFIG.md) - 高頻配置說明
- [KAFKA_UI_GUIDE.md](KAFKA_UI_GUIDE.md) - Kafka UI 使用指南
