# Kafka + ClickHouse 技術學習指南

> 本專案是學習 Apache Kafka 與 ClickHouse 整合的完整實作範例

## 目錄

- [技術棧概覽](#技術棧概覽)
- [Kafka 核心概念](#kafka-核心概念)
- [ClickHouse 核心概念](#clickhouse-核心概念)
- [Kafka + ClickHouse 整合](#kafka--clickhouse-整合)
- [本專案實作解析](#本專案實作解析)
- [實戰操作指令](#實戰操作指令)
- [進階學習方向](#進階學習方向)

---

## 技術棧概覽

### 專案使用的技術

| 技術 | 版本 | 用途 | 學習重點 |
|------|------|------|---------|
| **Apache Kafka** | 3.x (KRaft mode) | 訊息佇列、資料緩衝 | Producer/Consumer、Topic、Partition |
| **ClickHouse** | Latest | 時序資料庫、OLAP | Kafka Engine、Materialized View、MergeTree |
| **Grafana** | Latest | 資料視覺化 | Dashboard、Query Editor |
| **Python** | 3.8+ | 資料抓取與處理 | kafka-python、requests |
| **Docker** | Latest | 容器化部署 | docker-compose、容器網路 |

### 資料流架構

```
┌────────────────┐
│  Data Source   │  Steam API (或任何 API)
└───────┬────────┘
        │ HTTP GET
        ▼
┌────────────────┐
│ Python Producer│  kafka-python
└───────┬────────┘
        │ producer.send()
        ▼
┌────────────────────────────────────┐
│           Apache Kafka             │
│  ┌──────────────────────────────┐  │
│  │   Topic: steam_top_games     │  │  ← Partition 0
│  │   Partitions: 3              │  │  ← Partition 1
│  │   Replication: 1             │  │  ← Partition 2
│  └──────────────────────────────┘  │
└───────┬────────────────────────────┘
        │ Kafka Consumer (ClickHouse 內建)
        ▼
┌────────────────────────────────────┐
│          ClickHouse                │
│  ┌──────────────────────────────┐  │
│  │  1. Kafka Engine Table       │  │  ← 消費 Kafka
│  └──────────┬───────────────────┘  │
│             │                       │
│             ▼                       │
│  ┌──────────────────────────────┐  │
│  │  2. Materialized View        │  │  ← 自動轉換
│  └──────────┬───────────────────┘  │
│             │                       │
│             ▼                       │
│  ┌──────────────────────────────┐  │
│  │  3. MergeTree Table          │  │  ← 持久化儲存
│  └──────────────────────────────┘  │
└───────┬────────────────────────────┘
        │ ClickHouse Query
        ▼
┌────────────────┐
│    Grafana     │  SQL Query + 視覺化
└────────────────┘
```

---

## Kafka 核心概念

### 什麼是 Apache Kafka？

Apache Kafka 是一個**分散式串流平臺**，用於：
- ✅ 發布與訂閱訊息流（類似訊息佇列）
- ✅ 容錯式儲存訊息流
- ✅ 即時處理訊息流

### Kafka 核心元件

#### 1. Topic（主題）

- **定義**: 訊息的分類名稱，類似資料庫的「表」
- **特性**:
  - 一個 Kafka 可以有多個 Topic
  - Topic 可以有多個 Producer 和 Consumer
  - 訊息會保留一段時間（可設定）

**本專案範例**:
```bash
# 建立 Topic
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic steam_top_games_topic \
  --partitions 3 \
  --replication-factor 1
```

#### 2. Partition（分割槽）

- **定義**: Topic 的子分割槽，用於平行處理
- **作用**:
  - 提高吞吐量（多個 Partition 可平行讀寫）
  - 訊息順序保證（同一 Partition 內保證順序）
  - 負載平衡（訊息分散到不同 Partition）

**分割槽策略**:
```python
# Python Producer 範例
producer.send(
    'steam_top_games_topic',
    key=str(game_id).encode('utf-8'),  # 相同 key 會到同一 Partition
    value=json.dumps(data).encode('utf-8')
)
```

#### 3. Producer（生產者）

- **定義**: 傳送訊息到 Kafka 的應用程式
- **本專案範例**: `steam_top_games_producer.py`

**核心程式碼**:
```python
from kafka import KafkaProducer
import json

# 建立 Producer
producer = KafkaProducer(
    bootstrap_servers=['localhost:9092'],
    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
    acks='all',           # 確保訊息寫入成功
    retries=3,            # 失敗重試 3 次
    max_in_flight_requests_per_connection=1  # 保證順序
)

# 傳送訊息
future = producer.send('steam_top_games_topic', value=data)
record_metadata = future.get(timeout=10)  # 同步等待結果

# 關閉 Producer
producer.close()
```

**重要引數解析**:

| 引數 | 說明 | 推薦值 |
|------|------|--------|
| `bootstrap_servers` | Kafka 伺服器位址 | `['localhost:9092']` |
| `acks` | 寫入確認機制 | `'all'` (最安全) |
| `retries` | 失敗重試次數 | `3` |
| `compression_type` | 壓縮格式 | `'gzip'` 或 `'snappy'` |
| `batch_size` | 批次大小 | `16384` (16KB) |

#### 4. Consumer（消費者）

- **定義**: 從 Kafka 讀取訊息的應用程式
- **本專案範例**: ClickHouse 的 Kafka Engine Table

**Python Consumer 範例**（學習用）:
```python
from kafka import KafkaConsumer
import json

consumer = KafkaConsumer(
    'steam_top_games_topic',
    bootstrap_servers=['localhost:9092'],
    group_id='my-group',  # Consumer Group ID
    auto_offset_reset='earliest',  # 從最早的訊息開始讀
    value_deserializer=lambda m: json.loads(m.decode('utf-8'))
)

for message in consumer:
    print(f"Partition: {message.partition}")
    print(f"Offset: {message.offset}")
    print(f"Value: {message.value}")
```

#### 5. Consumer Group（消費者群組）

- **定義**: 多個 Consumer 組成的群組，共同消費 Topic
- **特性**:
  - 同一群組內的 Consumer 不會重複消費訊息
  - 不同群組的 Consumer 各自獨立消費
  - Partition 數量決定最大平行度

**範例**:
```
Topic: steam_top_games_topic (3 Partitions)
├── Consumer Group A
│   ├── Consumer 1 → Partition 0
│   ├── Consumer 2 → Partition 1
│   └── Consumer 3 → Partition 2
└── Consumer Group B
    └── Consumer 1 → Partition 0, 1, 2
```

### Kafka 實戰指令

```bash
# 1. 列出所有 Topics
kafka-topics --list --bootstrap-server localhost:9092

# 2. 檢視 Topic 詳細資訊
kafka-topics --describe \
  --topic steam_top_games_topic \
  --bootstrap-server localhost:9092

# 3. 檢視 Consumer Group 狀態
kafka-consumer-groups --describe \
  --group clickhouse_steam_top_games_consumer \
  --bootstrap-server localhost:9092

# 4. 手動消費訊息（測試用）
kafka-console-consumer \
  --topic steam_top_games_topic \
  --from-beginning \
  --bootstrap-server localhost:9092

# 5. 檢視 Partition 的 Offset
kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 \
  --topic steam_top_games_topic

# 6. 刪除 Topic（慎用！）
kafka-topics --delete \
  --topic steam_top_games_topic \
  --bootstrap-server localhost:9092
```

---

## ClickHouse 核心概念

### 什麼是 ClickHouse？

ClickHouse 是一個**列式資料庫管理系統 (DBMS)**，專為 **OLAP (分析型查詢)** 設計。

### 為什麼選擇 ClickHouse？

| 特性 | 說明 | 效能 |
|------|------|------|
| **列式儲存** | 只讀取需要的欄位 | 查詢快 10-100 倍 |
| **資料壓縮** | 壓縮比高達 10:1 | 節省 80% 磁碟空間 |
| **向量化執行** | SIMD 指令集加速 | CPU 使用率高 |
| **分散式查詢** | 支援叢集部署 | 水平擴充套件 |
| **即時寫入** | 支援高頻寫入 | 千萬級 QPS |

### ClickHouse 核心元件

#### 1. Table Engine（表引擎）

ClickHouse 的核心概念，決定了資料如何儲存和查詢。

**本專案使用的引擎**:

##### MergeTree（主要儲存引擎）

- **用途**: 持久化儲存、高效查詢
- **特性**:
  - 資料按 Primary Key 排序
  - 支援 Partition（分割槽）
  - 支援 TTL（自動過期）
  - 背景自動合併資料

**建立範例**:
```sql
CREATE TABLE steam_top_games (
    game_id UInt32,
    game_name String,
    current_players UInt32,
    peak_today UInt32,
    rank UInt16,
    fetch_time DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(fetch_time)  -- 按日分割槽
ORDER BY (game_id, fetch_time)       -- 排序鍵
TTL fetch_time + INTERVAL 90 DAY;    -- 90 天後自動刪除
```

**關鍵引數解析**:

| 引數 | 說明 | 範例 | 效果 |
|------|------|------|------|
| `PARTITION BY` | 分割槽鍵 | `toYYYYMMDD(fetch_time)` | 按日期建立目錄 |
| `ORDER BY` | 排序鍵 | `(game_id, fetch_time)` | 加速查詢 |
| `PRIMARY KEY` | 主鍵（可選） | `game_id` | 稀疏索引 |
| `TTL` | 資料保留時間 | `fetch_time + INTERVAL 90 DAY` | 自動清理 |

##### Kafka Engine（Kafka 整合引擎）

- **用途**: 消費 Kafka Topic
- **特性**:
  - 自動從 Kafka 讀取訊息
  - 支援多種資料格式（JSON, CSV, Avro 等）
  - 自動管理 Offset

**建立範例**:
```sql
CREATE TABLE kafka_steam_top_games (
    game_id UInt32,
    game_name String,
    current_players UInt32,
    peak_today UInt32,
    rank UInt16,
    fetch_time DateTime
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'localhost:9092',
    kafka_topic_list = 'steam_top_games_topic',
    kafka_group_name = 'clickhouse_steam_top_games_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;
```

**Kafka Engine 引數**:

| 引數 | 說明 | 範例 |
|------|------|------|
| `kafka_broker_list` | Kafka 位址 | `'localhost:9092'` |
| `kafka_topic_list` | Topic 名稱 | `'steam_top_games_topic'` |
| `kafka_group_name` | Consumer Group | `'clickhouse_consumer'` |
| `kafka_format` | 訊息格式 | `'JSONEachRow'` |
| `kafka_num_consumers` | Consumer 數量 | `1` 或 `3` |

**支援的資料格式**:
- `JSONEachRow`: 每行一個 JSON 物件（最常用）
- `CSV`: 逗號分隔
- `TSV`: Tab 分隔
- `Avro`: 二進位格式
- `Protobuf`: Protocol Buffers

#### 2. Materialized View（物化檢視）

- **定義**: 自動將資料從一個表轉換到另一個表
- **作用**: 連線 Kafka Engine 和 MergeTree 表

**建立範例**:
```sql
CREATE MATERIALIZED VIEW steam_top_games_mv TO steam_top_games AS
SELECT
    game_id,
    game_name,
    current_players,
    peak_today,
    rank,
    fetch_time
FROM kafka_steam_top_games;
```

**運作原理**:
```
Kafka → kafka_steam_top_games (Kafka Engine)
           ↓ (自動觸發)
        steam_top_games_mv (Materialized View)
           ↓ (寫入)
        steam_top_games (MergeTree)
```

#### 3. 資料型態

**常用型態**:

| ClickHouse 型態 | Python 對應 | 說明 | 範例 |
|----------------|-------------|------|------|
| `UInt8/16/32/64` | `int` | 無符號整數 | `rank UInt16` |
| `Int8/16/32/64` | `int` | 有符號整數 | `temperature Int16` |
| `Float32/64` | `float` | 浮點數 | `price Float32` |
| `String` | `str` | 字串 | `game_name String` |
| `DateTime` | `datetime` | 日期時間 | `fetch_time DateTime` |
| `Date` | `date` | 日期 | `date Date` |
| `Array(T)` | `list` | 陣列 | `genres Array(String)` |
| `Nullable(T)` | `Optional` | 可空值 | `email Nullable(String)` |

#### 4. SQL 函式

**時間函式**:
```sql
-- 取得當前時間
SELECT now();

-- 轉換時間格式
SELECT toYYYYMMDD(fetch_time) FROM steam_top_games;
SELECT toStartOfHour(fetch_time) FROM steam_top_games;
SELECT toStartOfDay(fetch_time) FROM steam_top_games;

-- 時間運算
SELECT now() - INTERVAL 1 DAY;
SELECT now() - INTERVAL 6 HOUR;
```

**聚合函式**:
```sql
-- 基本聚合
SELECT
    avg(current_players),
    sum(current_players),
    max(current_players),
    min(current_players),
    count()
FROM steam_top_games;

-- argMax: 找出某欄位最大值時的其他欄位值
SELECT argMax(game_name, current_players) FROM steam_top_games;
-- 意思是：找出 current_players 最大時對應的 game_name

-- uniq: 計算唯一值數量（近似）
SELECT uniq(game_id) FROM steam_top_games;
```

**陣列函式**:
```sql
-- arrayJoin: 將陣列展開為多行
SELECT arrayJoin(['Action', 'RPG', 'Strategy']) as genre;

-- has: 檢查陣列是否包含某元素
SELECT * FROM steam_game_details
WHERE has(genres, 'Action');

-- length: 陣列長度
SELECT length(genres) FROM steam_game_details;
```

---

## Kafka + ClickHouse 整合

### 整合架構

```
┌─────────────────────────────────────────────────────────┐
│                    完整資料管線                          │
└─────────────────────────────────────────────────────────┘

[1] Python Producer
    ↓ producer.send(topic, json_data)

[2] Kafka Topic (steam_top_games_topic)
    ↓ 訊息佇列

[3] ClickHouse Kafka Engine Table (kafka_steam_top_games)
    ↓ 自動消費 (kafka_num_consumers=1)

[4] Materialized View (steam_top_games_mv)
    ↓ 自動觸發轉換

[5] MergeTree Table (steam_top_games)
    ↓ 持久化儲存

[6] Grafana
    ↓ SQL 查詢視覺化
```

### 資料格式轉換

**Python → Kafka**:
```python
# Python 字典
data = {
    "game_id": 730,
    "game_name": "Counter-Strike 2",
    "current_players": 500000,
    "fetch_time": "2024-02-24 10:00:00"
}

# 轉換為 JSON 字串
json_string = json.dumps(data)
# → '{"game_id": 730, "game_name": "Counter-Strike 2", ...}'

# 編碼為 bytes
bytes_data = json_string.encode('utf-8')

# 傳送到 Kafka
producer.send('steam_top_games_topic', value=bytes_data)
```

**Kafka → ClickHouse**:
```sql
-- ClickHouse 自動解析 JSON（使用 JSONEachRow 格式）
-- Kafka 訊息: {"game_id": 730, "game_name": "CS2", ...}
-- ↓
-- ClickHouse 自動 mapping 到對應欄位:
-- game_id (UInt32) = 730
-- game_name (String) = "CS2"
```

### Consumer Offset 管理

**檢視 Offset**:
```bash
# 在 Kafka 容器中執行
kafka-consumer-groups --describe \
  --group clickhouse_steam_top_games_consumer \
  --bootstrap-server localhost:9092

# 輸出範例:
# TOPIC                   PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# steam_top_games_topic   0          1000            1000            0
# steam_top_games_topic   1          950             950             0
# steam_top_games_topic   2          1050            1050            0
```

**重置 Offset**（重新消費）:
```bash
# 重置到最早
kafka-consumer-groups --reset-offsets \
  --to-earliest \
  --group clickhouse_steam_top_games_consumer \
  --topic steam_top_games_topic \
  --execute

# 重置到指定 Offset
kafka-consumer-groups --reset-offsets \
  --to-offset 100 \
  --group clickhouse_steam_top_games_consumer \
  --topic steam_top_games_topic:0 \
  --execute
```

### 資料一致性保證

**Kafka 端**:
```python
producer = KafkaProducer(
    acks='all',  # 所有副本都確認寫入
    retries=3,   # 失敗重試
    max_in_flight_requests_per_connection=1  # 保證順序
)
```

**ClickHouse 端**:
```sql
-- 使用 ReplicatedMergeTree（叢集環境）
CREATE TABLE steam_top_games_replica (
    ...
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/steam_top_games', '{replica}')
PARTITION BY toYYYYMMDD(fetch_time)
ORDER BY (game_id, fetch_time);
```

---

## 本專案實作解析

### 完整 SQL 管線建立步驟

```sql
-- ============================================
-- 步驟 1: 建立 Kafka Engine Table
-- ============================================
CREATE TABLE kafka_steam_top_games (
    game_id UInt32,
    game_name String,
    current_players UInt32,
    peak_today UInt32,
    rank UInt16,
    fetch_time DateTime
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'localhost:9092',
    kafka_topic_list = 'steam_top_games_topic',
    kafka_group_name = 'clickhouse_steam_top_games_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;

-- ============================================
-- 步驟 2: 建立 MergeTree 實體表
-- ============================================
CREATE TABLE steam_top_games (
    game_id UInt32,
    game_name String,
    current_players UInt32,
    peak_today UInt32,
    rank UInt16,
    fetch_time DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(fetch_time)
ORDER BY (game_id, fetch_time)
TTL fetch_time + INTERVAL 90 DAY;

-- ============================================
-- 步驟 3: 建立 Materialized View
-- ============================================
CREATE MATERIALIZED VIEW steam_top_games_mv TO steam_top_games AS
SELECT
    game_id,
    game_name,
    current_players,
    peak_today,
    rank,
    fetch_time
FROM kafka_steam_top_games;

-- ============================================
-- 步驟 4: 驗證資料流
-- ============================================
-- 查詢 Kafka Engine（會消費一批訊息）
SELECT * FROM kafka_steam_top_games LIMIT 10;

-- 查詢 MergeTree（查詢持久化資料）
SELECT * FROM steam_top_games ORDER BY fetch_time DESC LIMIT 10;

-- 統計資料筆數
SELECT count() FROM steam_top_games;
```

### Python Producer 完整流程

```python
#!/usr/bin/env python3
import json
import time
from kafka import KafkaProducer
from kafka.errors import KafkaError
import requests

# 1. 建立 Kafka Producer
producer = KafkaProducer(
    bootstrap_servers=['localhost:9092'],
    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
    acks='all',
    retries=3
)

# 2. 抓取資料
response = requests.get('https://api.example.com/games', timeout=30)
games_data = response.json()

# 3. 處理並傳送到 Kafka
for game in games_data:
    # 格式化資料（必須符合 ClickHouse 表結構）
    record = {
        'game_id': game['id'],
        'game_name': game['name'],
        'current_players': game['players'],
        'peak_today': game['peak'],
        'rank': game['rank'],
        'fetch_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }

    # 傳送到 Kafka
    try:
        future = producer.send('steam_top_games_topic', value=record)
        record_metadata = future.get(timeout=10)
        print(f"✓ 傳送成功: {record['game_name']}")
    except KafkaError as e:
        print(f"✗ 傳送失敗: {e}")

# 4. 確保所有訊息都已傳送
producer.flush()
producer.close()
```

### 資料查詢範例

```sql
-- ============================================
-- 查詢 1: 最新的遊戲排行榜
-- ============================================
SELECT
    rank,
    game_name,
    current_players,
    fetch_time
FROM steam_top_games
WHERE fetch_time = (SELECT max(fetch_time) FROM steam_top_games)
ORDER BY rank ASC
LIMIT 20;

-- ============================================
-- 查詢 2: 特定遊戲的玩家數趨勢
-- ============================================
SELECT
    toStartOfHour(fetch_time) as hour,
    avg(current_players) as avg_players,
    max(current_players) as max_players
FROM steam_top_games
WHERE game_id = 730  -- CS2
  AND fetch_time >= now() - INTERVAL 24 HOUR
GROUP BY hour
ORDER BY hour DESC;

-- ============================================
-- 查詢 3: 每小時的資料更新頻率
-- ============================================
SELECT
    toStartOfHour(fetch_time) as hour,
    count() as record_count,
    count(DISTINCT game_id) as unique_games
FROM steam_top_games
WHERE fetch_time >= now() - INTERVAL 7 DAY
GROUP BY hour
ORDER BY hour DESC;

-- ============================================
-- 查詢 4: JOIN 兩個表（遊戲統計 + 遊戲詳情）
-- ============================================
SELECT
    g.game_name,
    g.current_players,
    d.original_price,
    d.discount_percent,
    d.review_score
FROM steam_top_games g
INNER JOIN (
    SELECT
        game_id,
        argMax(original_price, fetch_time) as original_price,
        argMax(discount_percent, fetch_time) as discount_percent,
        argMax(review_score, fetch_time) as review_score
    FROM steam_game_details
    GROUP BY game_id
) d ON g.game_id = d.game_id
WHERE g.fetch_time >= now() - INTERVAL 1 HOUR
ORDER BY g.current_players DESC
LIMIT 20;
```

---

## 實戰操作指令

### Kafka 管理指令

```bash
# ============================================
# Topic 管理
# ============================================

# 建立 Topic
docker exec kafka kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic steam_top_games_topic \
  --partitions 3 \
  --replication-factor 1

# 列出所有 Topics
docker exec kafka kafka-topics --list \
  --bootstrap-server localhost:9092

# 檢視 Topic 詳細資訊
docker exec kafka kafka-topics --describe \
  --topic steam_top_games_topic \
  --bootstrap-server localhost:9092

# 刪除 Topic
docker exec kafka kafka-topics --delete \
  --topic steam_top_games_topic \
  --bootstrap-server localhost:9092

# ============================================
# 訊息管理
# ============================================

# 手動傳送訊息（測試用）
docker exec -it kafka kafka-console-producer \
  --topic steam_top_games_topic \
  --bootstrap-server localhost:9092

# 手動消費訊息
docker exec kafka kafka-console-consumer \
  --topic steam_top_games_topic \
  --from-beginning \
  --bootstrap-server localhost:9092

# 消費最新的 10 筆訊息
docker exec kafka kafka-console-consumer \
  --topic steam_top_games_topic \
  --max-messages 10 \
  --bootstrap-server localhost:9092

# ============================================
# Consumer Group 管理
# ============================================

# 列出所有 Consumer Groups
docker exec kafka kafka-consumer-groups --list \
  --bootstrap-server localhost:9092

# 檢視 Consumer Group 詳情
docker exec kafka kafka-consumer-groups --describe \
  --group clickhouse_steam_top_games_consumer \
  --bootstrap-server localhost:9092

# 重置 Offset（重新消費）
docker exec kafka kafka-consumer-groups --reset-offsets \
  --to-earliest \
  --group clickhouse_steam_top_games_consumer \
  --topic steam_top_games_topic \
  --execute
```

### ClickHouse 管理指令

```bash
# ============================================
# 基本查詢
# ============================================

# 連線 ClickHouse Client
docker exec -it clickhouse-server clickhouse-client

# 或直接執行 SQL
docker exec clickhouse-server clickhouse-client --query "SHOW TABLES"

# 多行 SQL
docker exec -i clickhouse-server clickhouse-client --multiquery <<EOF
SHOW DATABASES;
USE default;
SHOW TABLES;
EOF

# ============================================
# 表管理
# ============================================

# 檢視錶結構
docker exec clickhouse-server clickhouse-client --query \
  "DESCRIBE TABLE steam_top_games"

# 檢視建表語句
docker exec clickhouse-server clickhouse-client --query \
  "SHOW CREATE TABLE steam_top_games"

# 檢視錶大小
docker exec clickhouse-server clickhouse-client --query \
  "SELECT
     table,
     formatReadableSize(sum(bytes)) as size,
     sum(rows) as rows
   FROM system.parts
   WHERE active AND table = 'steam_top_games'
   GROUP BY table"

# 刪除表
docker exec clickhouse-server clickhouse-client --query \
  "DROP TABLE IF EXISTS steam_top_games"

# ============================================
# Partition 管理
# ============================================

# 檢視 Partitions
docker exec clickhouse-server clickhouse-client --query \
  "SELECT
     partition,
     sum(rows) as rows,
     formatReadableSize(sum(bytes)) as size
   FROM system.parts
   WHERE table = 'steam_top_games' AND active
   GROUP BY partition
   ORDER BY partition DESC"

# 刪除特定 Partition
docker exec clickhouse-server clickhouse-client --query \
  "ALTER TABLE steam_top_games DROP PARTITION '20240224'"

# ============================================
# Kafka Engine 偵錯
# ============================================

# 檢視 Kafka Engine 狀態
docker exec clickhouse-server clickhouse-client --query \
  "SELECT * FROM system.kafka_consumers"

# 檢視錯誤日誌
docker exec clickhouse-server clickhouse-client --query \
  "SELECT * FROM system.text_log
   WHERE logger_name LIKE '%Kafka%'
   ORDER BY event_time DESC
   LIMIT 20"

# 手動觸發 Materialized View
docker exec clickhouse-server clickhouse-client --query \
  "SELECT * FROM kafka_steam_top_games LIMIT 100"
```

### 除錯技巧

```bash
# ============================================
# 檢查資料流
# ============================================

# 1. 檢查 Kafka 是否有訊息
docker exec kafka kafka-console-consumer \
  --topic steam_top_games_topic \
  --from-beginning \
  --max-messages 5 \
  --bootstrap-server localhost:9092

# 2. 檢查 ClickHouse Kafka Engine 是否消費
docker exec clickhouse-server clickhouse-client --query \
  "SELECT * FROM kafka_steam_top_games LIMIT 5"

# 3. 檢查 MergeTree 表是否有資料
docker exec clickhouse-server clickhouse-client --query \
  "SELECT count() FROM steam_top_games"

# 4. 檢視最新資料
docker exec clickhouse-server clickhouse-client --query \
  "SELECT * FROM steam_top_games
   ORDER BY fetch_time DESC
   LIMIT 10 FORMAT Pretty"

# ============================================
# 效能分析
# ============================================

# 查詢執行計畫
docker exec clickhouse-server clickhouse-client --query \
  "EXPLAIN SELECT * FROM steam_top_games
   WHERE game_id = 730 AND fetch_time >= now() - INTERVAL 1 DAY"

# 查詢效能統計
docker exec clickhouse-server clickhouse-client --query \
  "SELECT
     query,
     query_duration_ms,
     read_rows,
     read_bytes
   FROM system.query_log
   WHERE type = 'QueryFinish'
   ORDER BY event_time DESC
   LIMIT 10 FORMAT Pretty"
```

---

## 進階學習方向

### Kafka 進階主題

#### 1. 效能調優
```python
producer = KafkaProducer(
    # 批次大小（增加吞吐量）
    batch_size=32768,  # 32KB
    linger_ms=100,     # 等待 100ms 累積訊息

    # 壓縮（節省網路頻寬）
    compression_type='gzip',  # 或 'snappy', 'lz4'

    # 緩衝區大小
    buffer_memory=67108864,  # 64MB
)
```

#### 2. 分割槽策略
```python
from kafka.partitioner import Murmur2Partitioner

producer = KafkaProducer(
    partitioner=Murmur2Partitioner(),  # 自訂分割槽器
)

# 自訂分割槽邏輯
def custom_partitioner(key, all_partitions, available_partitions):
    return hash(key) % len(all_partitions)
```

#### 3. 事務支援
```python
producer = KafkaProducer(
    transactional_id='my-transactional-id',
    enable_idempotence=True
)

producer.init_transactions()
producer.begin_transaction()
try:
    producer.send('topic1', value=msg1)
    producer.send('topic2', value=msg2)
    producer.commit_transaction()
except Exception:
    producer.abort_transaction()
```

### ClickHouse 進階主題

#### 1. 叢集部署
```sql
-- 建立分散式表
CREATE TABLE steam_top_games_distributed AS steam_top_games
ENGINE = Distributed(cluster_name, default, steam_top_games, rand());
```

#### 2. 物化檢視進階用法
```sql
-- 聚合物化檢視（預先計算）
CREATE MATERIALIZED VIEW steam_hourly_stats
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMMDD(hour)
ORDER BY (hour, game_id)
AS SELECT
    toStartOfHour(fetch_time) as hour,
    game_id,
    sum(current_players) as total_players,
    count() as records
FROM steam_top_games
GROUP BY hour, game_id;
```

#### 3. 索引最佳化
```sql
-- Skipping Index（跳過索引）
ALTER TABLE steam_top_games
ADD INDEX idx_game_name game_name TYPE bloom_filter GRANULARITY 4;

-- 使用索引查詢
SELECT * FROM steam_top_games
WHERE game_name = 'Counter-Strike 2';
```

### 學習資源

**官方檔案**:
- Apache Kafka: https://kafka.apache.org/documentation/
- ClickHouse: https://clickhouse.com/docs/
- kafka-python: https://kafka-python.readthedocs.io/

**推薦書籍**:
- 《Kafka: The Definitive Guide》
- 《ClickHouse in Action》

**線上課程**:
- Confluent Kafka 官方教學
- ClickHouse 官方 Webinar

**實戰練習**:
1. 擴充套件本專案，增加更多資料來源
2. 實作 Kafka 叢集（3 個 Broker）
3. 實作 ClickHouse 叢集（Shard + Replica）
4. 使用 Kafka Connect 整合其他系統
5. 實作即時告警系統（Grafana Alerts）

---

## 總結

本專案完整展示了 **Kafka + ClickHouse** 的整合應用，涵蓋：

✅ **Kafka**: Topic、Producer、Consumer、Partition、Offset
✅ **ClickHouse**: Kafka Engine、Materialized View、MergeTree
✅ **資料管線**: API → Kafka → ClickHouse → Grafana
✅ **實戰技能**: Docker 容器化、Python 開發、SQL 查詢

透過本專案，你已經掌握了現代資料工程的核心技術棧！

---

**專案作者**: 資深資料工程師
**最後更新**: 2024-02-24
