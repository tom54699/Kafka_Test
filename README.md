# Steam 資料管線 POC 專案

本專案是一個基於 Kafka + ClickHouse + Grafana 的即時資料管線系統，用於追蹤和視覺化 Steam 遊戲平臺的熱門遊戲統計資料。

## 📚 文件導航

- [📖 完整文件索引](DOCS_INDEX.md) - 檢視所有文件
- [🚀 快速開始](QUICK_START.md) - 5分鐘快速部署
- [📜 指令碼使用指南](SCRIPTS_GUIDE.md) - 所有指令碼的詳細說明
- [⚙️ 高頻配置](HIGH_FREQUENCY_CONFIG.md) - 壓力測試和效能調優
- [📊 Kafka UI 指南](KAFKA_UI_GUIDE.md) - 監控 Kafka 訊息流

## 專案架構

```
Steam API → Python Producers → Kafka Topics → ClickHouse → Grafana Dashboard
```

### 資料流說明

1. **Python Producers** - 兩個獨立的微服務定期抓取 Steam 資料
   - `steam_top_games_producer.py`: 每 10 分鐘抓取熱門遊戲的即時玩家數
   - `steam_game_details_producer.py`: 每 1 小時抓取遊戲詳細資訊（價格、評價等）

2. **Kafka Topics** - 訊息佇列緩衝
   - `steam_top_games_topic`: 熱門遊戲玩家統計
   - `steam_game_details_topic`: 遊戲詳細資訊

3. **ClickHouse** - 高效能時序資料庫
   - Kafka Engine Table: 消費 Kafka 訊息
   - Materialized View: 自動轉換資料
   - MergeTree Table: 長期儲存與查詢

4. **Grafana** - 視覺化儀錶板
   - 即時監控熱門遊戲排行
   - 玩家數趨勢分析
   - 折扣遊戲推薦
   - 遊戲評價分析

## 技術棧

- **訊息佇列**: Apache Kafka (KRaft mode)
- **資料庫**: ClickHouse
- **視覺化**: Grafana
- **開發語言**: Python 3.x
- **主要函式庫**:
  - kafka-python
  - requests
  - logging

## 快速開始

### 🎯 兩種啟動方式

#### 方式 1: 一鍵自動化部署（推薦）
```bash
./setup.sh
```
這個指令碼會自動完成所有初始化工作（詳見 [SCRIPTS_GUIDE.md](SCRIPTS_GUIDE.md)）

#### 方式 2: 手動逐步部署
按照下面的步驟手動執行

---

### 1. 環境需求

- Docker & Docker Compose
- Python 3.8+
- pip

### 2. 啟動基礎設施

使用 docker-compose 啟動 Kafka、ClickHouse 和 Grafana：

```bash
docker-compose up -d
```

服務啟動後：
- Kafka: `localhost:9092`
- Kafka UI: `http://localhost:8080` (Kafka 管理介面)
- ClickHouse HTTP: `localhost:8123`
- ClickHouse Native: `localhost:9000`
- Grafana: `http://localhost:3000`

### 3. 建立 ClickHouse Schema

執行 SQL 指令碼建立資料表和資料管線：

```bash
# 方法 1: 使用 ClickHouse Client (如果已安裝)
clickhouse-client --host localhost --port 9000 --multiquery < clickhouse_schema.sql

# 方法 2: 使用 HTTP API
cat clickhouse_schema.sql | curl 'http://localhost:8123/' --data-binary @-

# 方法 3: 使用 Docker 容器內的 client
docker exec -i clickhouse-server clickhouse-client --multiquery < clickhouse_schema.sql
```

驗證資料表是否建立成功：

```bash
clickhouse-client --host localhost --port 9000 --query "SHOW TABLES"
```

應該會看到：
- kafka_steam_top_games
- steam_top_games
- steam_top_games_mv
- kafka_steam_game_details
- steam_game_details
- steam_game_details_mv

### 4. 建立 Kafka Topics

```bash
# 進入 Kafka 容器
docker exec -it kafka bash

# 建立 Topic 1: steam_top_games_topic
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic steam_top_games_topic \
  --partitions 3 \
  --replication-factor 1

# 建立 Topic 2: steam_game_details_topic
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic steam_game_details_topic \
  --partitions 3 \
  --replication-factor 1

# 驗證 Topics
kafka-topics --list --bootstrap-server localhost:9092

# 離開容器
exit
```

### 5. 安裝 Python 依賴套件

```bash
pip install kafka-python requests
```

或使用 requirements.txt：

```bash
# 建立 requirements.txt
cat > requirements.txt << EOF
kafka-python==2.0.2
requests==2.31.0
EOF

# 安裝
pip install -r requirements.txt
```

### 6. 啟動 Python Producers

#### 選項 A: 真實資料採集（生產環境）

使用指令碼啟動：
```bash
./start_producers.sh
```

或手動啟動：
```bash
# 背景執行
nohup python steam_top_games_producer.py > logs/top_games.log 2>&1 &
nohup python steam_game_details_producer.py > logs/game_details.log 2>&1 &

# 檢視日誌
tail -f logs/top_games.log
tail -f logs/game_details.log
```

**資料量**: ~12 條/分鐘（受 Steam API 限制）

#### 選項 B: 假資料生成（壓力測試）

使用假資料生成器進行壓力測試：
```bash
./start_fake_producers.sh
```

**資料量**: 30,000 條/秒（可配置）

**停止 Producers**:
```bash
./stop_producers.sh
```

詳細說明見 [SCRIPTS_GUIDE.md](SCRIPTS_GUIDE.md)

### 7. 驗證資料流

等待 1-2 分鐘後，查詢 ClickHouse 確認資料是否正常寫入：

```bash
# 查詢熱門遊戲資料筆數
clickhouse-client --host localhost --port 9000 --query \
  "SELECT count() FROM steam_top_games"

# 檢視最新的 10 筆遊戲資料
clickhouse-client --host localhost --port 9000 --query \
  "SELECT game_name, current_players, rank, fetch_time
   FROM steam_top_games
   ORDER BY fetch_time DESC
   LIMIT 10 FORMAT Pretty"

# 查詢遊戲詳細資訊筆數
clickhouse-client --host localhost --port 9000 --query \
  "SELECT count() FROM steam_game_details"
```

### 8. 設定 Grafana Dashboard

1. 開啟瀏覽器訪問 `http://localhost:3000`
2. 預設帳號密碼: `admin` / `admin`
3. ClickHouse Data Source 會由 `grafana_datasource.yaml` 自動建立
   - 名稱: `ClickHouse`
   - Host: `clickhouse`（不要填 `http://`）
   - Port: `8123`
   - Database: `default`
   - 如果你之前手動建過錯誤的 Data Source，先刪掉後重整頁面

4. Dashboard 會由 provisioning 自動載入：
   - Provider 設定：`grafana_dashboard_provider.yaml`
   - Dashboard JSON：`grafana_dashboards/steam-kafka-clickhouse-overview.json`
   - 若你是第一次加上這兩個檔案，請重啟 Grafana：
     - `docker compose restart grafana`

5. 在 Grafana 左側選單開啟 Dashboards：
   - Folder: `Steam`
   - Dashboard: `Steam Kafka ClickHouse Overview`

6. Explore 模式快速查詢：
   - 在 Explore 貼上 `grafana_explore_queries.sql` 內的查詢
   - 這些查詢都只使用 `steam_*` 實體表，不會觸發 `Code: 620`

7. 若你想自行擴充 Panel，可參考 `grafana_queries.sql`：
   - **Row 1**: 總覽統計 (4 個 Stat Panels)
     - 總玩家數
     - 追蹤遊戲數
     - 平均折扣
     - 平均評價
   - **Row 2**: 熱門遊戲排行榜 (Table)
   - **Row 3**: 玩家數時間序列 (Time Series)
   - **Row 4**: 折扣遊戲 + 遊戲型別分佈 (Table + Pie Chart)

## 專案檔案說明

```
.
├── 📄 配置檔案
│   ├── docker-compose.yml                         # Docker 基礎設施設定
│   ├── clickhouse_schema.sql                      # ClickHouse 資料表定義
│   ├── grafana_dashboard_provider.yaml            # Grafana Dashboard Provider
│   ├── grafana_datasource.yaml                    # Grafana 資料來源配置
│   └── requirements.txt                           # Python 依賴包
│
├── 📜 指令碼檔案
│   ├── setup.sh                                   # 一鍵初始化指令碼
│   ├── start_producers.sh                         # 啟動真實資料 Producers
│   ├── start_fake_producers.sh                    # 啟動假資料生成器
│   ├── stop_producers.sh                          # 停止所有 Producers
│   └── recreate_kafka_tables.sh                   # 重建 Kafka Engine 表
│
├── 🐍 Python 程式
│   ├── steam_top_games_producer.py                # 真實資料：熱門遊戲統計
│   ├── steam_game_details_producer.py             # 真實資料：遊戲詳細資訊
│   ├── fake_steam_top_games_producer.py           # 假資料生成器：熱門遊戲
│   └── fake_steam_game_details_producer.py        # 假資料生成器：遊戲詳情
│
├── 📊 Grafana 相關
│   ├── grafana_dashboards/                        # Dashboard JSON 檔案
│   │   └── steam-kafka-clickhouse-overview.json
│   ├── grafana_explore_queries.sql                # Explore 快速查詢範本
│   └── grafana_queries.sql                        # Dashboard 查詢範例
│
└── 📚 文件
    ├── README.md                                  # 專案總覽（本檔案）
    ├── DOCS_INDEX.md                              # 文件索引
    ├── SCRIPTS_GUIDE.md                           # 指令碼使用指南
    ├── QUICK_START.md                             # 快速入門
    ├── PROJECT_OVERVIEW.md                        # 專案架構概覽
    ├── HIGH_FREQUENCY_CONFIG.md                   # 高頻配置說明
    ├── KAFKA_UI_GUIDE.md                          # Kafka UI 使用指南
    ├── KAFKA_CLICKHOUSE_LEARNING_GUIDE.md         # 學習指南
    ├── GRAFANA_CLICKHOUSE_STEP_BY_STEP.md         # Grafana 配置步驟
    └── ENV_SETUP_GUIDE.md                         # 環境設定指南
```

## 資料結構

### steam_top_games 表

| 欄位 | 型態 | 說明 |
|------|------|------|
| game_id | UInt32 | Steam AppID |
| game_name | String | 遊戲名稱 |
| current_players | UInt32 | 當前玩家數 |
| peak_today | UInt32 | 今日峰值 |
| rank | UInt16 | 排名 |
| fetch_time | DateTime | 抓取時間 |

### steam_game_details 表

| 欄位 | 型態 | 說明 |
|------|------|------|
| game_id | UInt32 | Steam AppID |
| game_name | String | 遊戲名稱 |
| short_description | String | 簡短描述 |
| release_date | String | 發行日期 |
| developers | Array(String) | 開發商 |
| publishers | Array(String) | 發行商 |
| genres | Array(String) | 遊戲型別 |
| original_price | Float32 | 原價 |
| discount_percent | UInt8 | 折扣百分比 |
| final_price | Float32 | 最終價格 |
| positive_reviews | UInt32 | 正面評價數 |
| negative_reviews | UInt32 | 負面評價數 |
| total_reviews | UInt32 | 總評價數 |
| review_score | Float32 | 評價分數 |
| fetch_time | DateTime | 抓取時間 |

## 常見問題與疑難排解

### 1. Kafka 連線失敗

**錯誤訊息**: `KafkaError: Unable to connect to Kafka`

**解決方法**:
- 確認 Kafka 容器正在執行: `docker ps | grep kafka`
- 檢查 Kafka 是否監聽 9092 埠: `netstat -an | grep 9092`
- 確認 docker-compose.yml 中的埠號對映正確

### 2. ClickHouse 無法寫入資料

**症狀**: Producer 正常執行，但 ClickHouse 表中無資料

**檢查步驟**:
```bash
# 1. 確認 Kafka Engine 表是否正常消費
clickhouse-client --query "SELECT * FROM kafka_steam_top_games LIMIT 10"

# 2. 檢查 Materialized View 是否正常
clickhouse-client --query "SHOW CREATE TABLE steam_top_games_mv"

# 3. 檢視 ClickHouse 日誌
docker logs clickhouse-server
```

### 3. Steam API Rate Limit

**症狀**: Producer 日誌顯示大量請求失敗

**解決方法**:
- 增加請求之間的等待時間（目前為 1.5 秒）
- 減少抓取的遊戲數量
- 分散請求到不同時段

### 4. 資料延遲問題

**症狀**: Grafana 顯示的資料有明顯延遲

**檢查**:
- 確認 ClickHouse Kafka Engine 的 `kafka_num_consumers` 設定
- 檢查 ClickHouse 系統資源使用率
- 調整 Grafana 的自動重新整理頻率

## 效能調優建議

### ClickHouse

1. **增加 Kafka Consumers**:
```sql
-- 修改 kafka_num_consumers 設定
ALTER TABLE kafka_steam_top_games MODIFY SETTING kafka_num_consumers = 3;
```

2. **調整 TTL 保留時間**:
```sql
-- 如果磁碟空間不足，可縮短保留時間
ALTER TABLE steam_top_games MODIFY TTL fetch_time + INTERVAL 30 DAY;
```

3. **建立索引**:
```sql
-- 為常用查詢欄位建立 Skipping Index
ALTER TABLE steam_top_games ADD INDEX idx_game_name game_name TYPE bloom_filter GRANULARITY 4;
```

### Python Producers

1. **使用非同步傳送**:
   - 將 `future.get(timeout=10)` 改為非同步模式以提升吞吐量

2. **批次傳送**:
   - 累積多筆資料後一次性傳送，減少網路開銷

3. **多執行緒處理**:
   - 使用 threading 或 multiprocessing 並行處理遊戲資料

## 擴充套件功能建議

1. **即時警報**:
   - 在 Grafana 設定 Alert Rules，當特定遊戲玩家數超過閾值時傳送通知

2. **歷史資料分析**:
   - 保留更長時間的資料，分析遊戲熱度的季節性變化

3. **價格追蹤**:
   - 追蹤遊戲價格變化，找出最佳購買時機

4. **玩家預測**:
   - 使用機器學習模型預測遊戲未來的玩家數趨勢

## 授權與免責宣告

本專案僅供學習和研究使用。使用 Steam API 時請遵守 [Steam Web API 使用條款](https://steamcommunity.com/dev/apiterms)。

## 相關資源

- [Apache Kafka 官方檔案](https://kafka.apache.org/documentation/)
- [ClickHouse 官方檔案](https://clickhouse.com/docs/)
- [Grafana 官方檔案](https://grafana.com/docs/)
- [Steam Web API 檔案](https://developer.valvesoftware.com/wiki/Steam_Web_API)
- [Steam Spy API](https://steamspy.com/api.php)

## 貢獻

歡迎提交 Issue 和 Pull Request！

## 作者

資深資料工程師 - Steam 資料管線 POC 專案
