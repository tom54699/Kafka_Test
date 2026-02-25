# Steam 資料管線專案概覽

## 專案簡介

這是一個完整的即時資料管線 POC 專案，展示如何使用現代資料工程技術棧建立微服務資料匯流平臺。

### 核心價值

- **即時性**: 10 分鐘更新一次熱門遊戲玩家統計
- **可擴充套件**: 微服務架構，易於橫向擴充套件
- **高效能**: ClickHouse 提供毫秒級查詢響應
- **視覺化**: Grafana 提供豐富的圖表和儀錶板

## 技術架構

```
┌─────────────────┐
│   Steam API     │  (資料來源)
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Python Producers (微服務)       │
│  ├─ steam_top_games_producer    │  每 10 分鐘執行
│  └─ steam_game_details_producer │  每 1 小時執行
└────────┬────────────────────────┘
         │ JSON Messages
         ▼
┌─────────────────────────────────┐
│      Apache Kafka               │  (訊息佇列)
│  ├─ steam_top_games_topic       │
│  └─ steam_game_details_topic    │
└────────┬────────────────────────┘
         │ Stream Processing
         ▼
┌─────────────────────────────────┐
│      ClickHouse                 │  (時序資料庫)
│  ├─ Kafka Engine Tables         │  消費 Kafka
│  ├─ Materialized Views          │  資料轉換
│  └─ MergeTree Tables            │  持久化儲存
└────────┬────────────────────────┘
         │ SQL Queries
         ▼
┌─────────────────────────────────┐
│        Grafana                  │  (視覺化)
│  ├─ Dashboards                  │
│  ├─ Alerts                      │
│  └─ Reports                     │
└─────────────────────────────────┘
```

## 資料流詳解

### 1. 資料抓取層 (Data Collection)

**steam_top_games_producer.py**
- 資料來源: Steam Spy API + Steam Web API
- 執行頻率: 每 10 分鐘
- 資料內容: Top 100 遊戲的即時玩家數
- 處理邏輯:
  1. 從 Steam Spy 獲取熱門遊戲列表
  2. 逐一查詢每款遊戲的即時玩家數
  3. 格式化為 JSON 並傳送到 Kafka
- Rate Limit 控制: 每 10 個請求休息 1 秒

**steam_game_details_producer.py**
- 資料來源: Steam Store API
- 執行頻率: 每 1 小時
- 資料內容: 遊戲詳細資訊（價格、評價、開發商等）
- 處理邏輯:
  1. 獲取熱門遊戲 AppID 列表
  2. 查詢每款遊戲的 Store API
  3. 解析價格、評價、型別等資訊
  4. 傳送到 Kafka
- Rate Limit 控制: 每個請求間隔 1.5 秒

### 2. 訊息佇列層 (Message Queue)

**Kafka Topics 設計**

| Topic | Partitions | Replication | 資料型別 | 更新頻率 |
|-------|-----------|-------------|---------|---------|
| steam_top_games_topic | 3 | 1 | 玩家統計 | 10 分鐘 |
| steam_game_details_topic | 3 | 1 | 遊戲詳情 | 1 小時 |

**為什麼使用 Kafka?**
- 解耦生產者和消費者
- 資料緩衝，避免 ClickHouse 寫入壓力
- 支援多個消費者（未來可擴充套件）
- 資料持久化，防止資料遺失

### 3. 資料儲存層 (Data Storage)

**ClickHouse 資料管線架構**

```
Kafka Topic
    ↓
Kafka Engine Table (消費 Kafka 訊息)
    ↓
Materialized View (自動觸發轉換)
    ↓
MergeTree Table (持久化儲存)
```

**資料表設計**

**steam_top_games** (玩家統計表)
- 分割槽鍵: `toYYYYMMDD(fetch_time)` - 按日分割槽
- 排序鍵: `(game_id, fetch_time)` - 最佳化遊戲查詢
- TTL: 90 天 - 自動清理舊資料
- 預估資料量: 100 遊戲 × 6 次/小時 × 24 小時 = 14,400 筆/天

**steam_game_details** (遊戲詳情表)
- 分割槽鍵: `toYYYYMM(fetch_time)` - 按月分割槽
- 排序鍵: `(game_id, fetch_time)` - 最佳化遊戲查詢
- TTL: 180 天 - 保留更長時間
- 預估資料量: 100 遊戲 × 24 次/天 = 2,400 筆/天

**為什麼使用 ClickHouse?**
- 列式儲存，壓縮比高（節省 80% 空間）
- 時序資料查詢速度快（毫秒級）
- 原生支援 Kafka Engine
- SQL 相容，易於使用

### 4. 視覺化層 (Visualization)

**Grafana Dashboard 設計**

**Panel 型別與用途**

| Panel 型別 | 用途 | 資料來源 | 重新整理頻率 |
|-----------|------|---------|---------|
| Stat | 總覽統計 | steam_top_games | 1 分鐘 |
| Table | 遊戲排行榜 | steam_top_games | 1 分鐘 |
| Time Series | 玩家數趨勢 | steam_top_games | 1 分鐘 |
| Bar Chart | 型別分佈 | JOIN 兩表 | 5 分鐘 |
| Pie Chart | 遊戲型別佔比 | steam_game_details | 5 分鐘 |

**關鍵查詢最佳化**
- 使用 `argMax()` 獲取最新資料，避免排序
- 使用 `$__timeFilter()` 限制時間範圍
- 建立 Grafana 變數，實現動態過濾
- 合理設定 auto-refresh 頻率

## 專案檔案結構

```
kafka/
├── README.md                           # 專案說明檔案
├── PROJECT_OVERVIEW.md                 # 專案概覽（本檔案）
├── docker-compose.yml                  # 基礎設施定義
├── clickhouse_schema.sql               # ClickHouse 資料表定義
├── grafana_queries.sql                 # Grafana 查詢範例
├── requirements.txt                    # Python 依賴套件
├── .gitignore                          # Git 忽略檔案
│
├── steam_top_games_producer.py         # 熱門遊戲統計 Producer
├── steam_game_details_producer.py      # 遊戲詳情 Producer
│
├── setup.sh                            # 快速設定指令碼
├── start_producers.sh                  # 啟動 Producers
├── stop_producers.sh                   # 停止 Producers
│
└── logs/                               # 日誌目錄（執行時自動建立）
    ├── top_games.log
    └── game_details.log
```

## 資料模型

### steam_top_games (玩家統計)

```sql
CREATE TABLE steam_top_games (
    game_id UInt32,              -- Steam AppID
    game_name String,            -- 遊戲名稱
    current_players UInt32,      -- 當前玩家數
    peak_today UInt32,           -- 今日峰值
    rank UInt16,                 -- 排名 (1-100)
    fetch_time DateTime          -- 抓取時間
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(fetch_time)
ORDER BY (game_id, fetch_time);
```

**查詢範例**: 查詢 CS2 過去 24 小時玩家數變化
```sql
SELECT
    fetch_time,
    current_players
FROM steam_top_games
WHERE game_id = 730
  AND fetch_time >= now() - INTERVAL 24 HOUR
ORDER BY fetch_time;
```

### steam_game_details (遊戲詳情)

```sql
CREATE TABLE steam_game_details (
    game_id UInt32,              -- Steam AppID
    game_name String,            -- 遊戲名稱
    developers Array(String),    -- 開發商列表
    publishers Array(String),    -- 發行商列表
    genres Array(String),        -- 遊戲型別列表
    original_price Float32,      -- 原價 (USD)
    discount_percent UInt8,      -- 折扣百分比
    final_price Float32,         -- 最終價格 (USD)
    review_score Float32,        -- 評價分數 (0-100)
    total_reviews UInt32,        -- 總評價數
    fetch_time DateTime          -- 抓取時間
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(fetch_time)
ORDER BY (game_id, fetch_time);
```

**查詢範例**: 查詢目前有折扣且評價高的遊戲
```sql
SELECT
    game_name,
    original_price,
    discount_percent,
    final_price,
    review_score
FROM steam_game_details
WHERE fetch_time >= now() - INTERVAL 1 DAY
  AND discount_percent > 0
  AND review_score >= 80
ORDER BY discount_percent DESC
LIMIT 20;
```

## 效能指標

### 預估資源使用

**資料量**
- 每日新增: ~17,000 筆資料
- 每月新增: ~510,000 筆資料
- 預估壓縮後: ~50 MB/月

**CPU & 記憶體**
- Python Producers: ~100 MB RAM each
- Kafka: ~512 MB RAM
- ClickHouse: ~1 GB RAM
- Grafana: ~256 MB RAM
- **總計**: ~2 GB RAM

**網路頻寬**
- Steam API 請求: ~1 KB/request
- Kafka 訊息: ~500 bytes/message
- ClickHouse 查詢: ~10 KB/query
- **總計**: <1 Mbps

### 查詢效能

**測試環境**: MacBook Pro M1, 16GB RAM

| 查詢型別 | 資料範圍 | 平均響應時間 |
|---------|---------|------------|
| 最新排行榜 | 100 筆 | <10 ms |
| 24 小時趨勢 | 144 筆 | <20 ms |
| 7 天趨勢 | 1,008 筆 | <50 ms |
| 30 天聚合 | 4,320 筆 | <100 ms |
| JOIN 查詢 | 100 筆 | <30 ms |

## 監控與告警

### 關鍵指標

**Producer 健康度**
- 抓取成功率 > 95%
- API 回應時間 < 5 秒
- Kafka 傳送成功率 = 100%

**Kafka 健康度**
- Topic Lag < 100 messages
- Producer/Consumer 吞吐量穩定
- 無錯誤日誌

**ClickHouse 健康度**
- 寫入延遲 < 5 秒
- 查詢響應時間 < 100 ms
- 磁碟使用率 < 80%

### Grafana 告警設定

**建議告警規則**
1. 熱門遊戲玩家數異常波動 (±50%)
2. 資料更新延遲 > 30 分鐘
3. ClickHouse 查詢失敗率 > 1%

## 擴充套件方向

### 短期擴充套件 (1-2 週)

1. **增加資料維度**
   - 遊戲成就完成度統計
   - 遊戲工作坊內容數量
   - 遊戲社群討論熱度

2. **改善視覺化**
   - 遊戲型別趨勢分析
   - 價格歷史追蹤
   - 折扣預測模型

3. **效能最佳化**
   - 實作 Producer 非同步傳送
   - 增加 ClickHouse Kafka Consumers
   - 建立 ClickHouse Skipping Index

### 中期擴充套件 (1-2 月)

1. **機器學習應用**
   - 玩家數預測模型
   - 遊戲熱度分類
   - 價格趨勢預測

2. **多區域支援**
   - 追蹤不同區域的價格差異
   - 分析區域玩家偏好

3. **社群功能**
   - 遊戲推薦系統
   - 折扣提醒通知
   - 玩家社群分析

### 長期擴充套件 (3-6 月)

1. **多平臺整合**
   - Epic Games Store
   - GOG
   - PlayStation Store
   - Xbox Store

2. **商業應用**
   - 遊戲市場分析報告
   - 開發商競爭分析
   - 玩家行為洞察

3. **雲端部署**
   - Kubernetes 容器編排
   - 多區域部署
   - 自動擴充套件

## 學習價值

這個專案適合以下學習目標：

### 資料工程
- Kafka 訊息佇列設計
- ClickHouse 時序資料庫應用
- 資料管線架構設計
- ETL 流程實作

### 後端開發
- Python 微服務開發
- API 整合與錯誤處理
- 非同步程式設計
- 日誌與監控

### DevOps
- Docker 容器化
- Docker Compose 編排
- Shell 指令碼自動化
- 服務監控與告警

### 資料視覺化
- Grafana Dashboard 設計
- SQL 查詢最佳化
- 時序圖表設計
- 互動式儀錶板

## 常見應用場景

1. **遊戲玩家**: 追蹤喜愛遊戲的熱度變化
2. **遊戲開發者**: 分析競品遊戲的表現
3. **遊戲評論者**: 獲取遊戲統計資料
4. **資料分析師**: 學習即時資料管線技術
5. **投資者**: 分析遊戲市場趨勢

## 總結

這是一個完整的生產級資料管線 POC 專案，展示瞭如何：
- 設計可擴充套件的微服務架構
- 實作即時資料流處理
- 建立高效能時序資料庫
- 建立互動式視覺化儀錶板

專案程式碼完整、檔案齊全、易於部署，適合作為學習和參考範例。
