# Kafka UI 使用指南

## 什麼是 Kafka UI？

Kafka UI 是一個開源的 Kafka 管理介面，可以視覺化地監控和管理 Kafka。

### 功能特色

- ✅ 檢視所有 Topics 列表
- ✅ 即時檢視訊息內容
- ✅ 監控 Consumer Groups 狀態
- ✅ 檢視 Brokers 資訊
- ✅ 手動傳送測試訊息
- ✅ 管理 Topics（建立、刪除、設定）
- ✅ 檢視 Consumer Lag（延遲）

---

## 啟動 Kafka UI

### 方法 1: 重新啟動所有服務（推薦）

```bash
# 重新啟動 docker-compose
docker-compose down
docker-compose up -d

# 檢查 Kafka UI 狀態
docker ps | grep kafka-ui
```

### 方法 2: 只啟動 Kafka UI

```bash
# 啟動 Kafka UI
docker-compose up -d kafka-ui

# 檢視啟動日誌
docker logs -f kafka-ui
```

---

## 存取 Kafka UI

### 開啟瀏覽器

訪問：**http://localhost:8080**

不需要帳號密碼，直接開啟即可使用。

---

## Kafka UI 主要功能介紹

### 1. 主頁 Dashboard

顯示整體狀態：
- Brokers 數量
- Topics 數量
- Consumer Groups 數量
- 訊息總數

### 2. Topics 管理

**檢視 Topics 列表**
- 點選左側選單 **Topics**
- 可看到所有 Topics：
  - `steam_top_games_topic`
  - `steam_game_details_topic`

**檢視 Topic 詳情**
- 點選 Topic 名稱
- 可看到：
  - Partitions 數量
  - Replication Factor
  - 訊息總數
  - 各 Partition 的 Offset

**檢視訊息內容**
1. 點選 Topic 名稱
2. 點選 **Messages** 頁籤
3. 點選 **Fetch Messages**
4. 可看到實際的 JSON 訊息內容

範例訊息：
```json
{
  "game_id": 730,
  "game_name": "Counter-Strike 2",
  "current_players": 500000,
  "peak_today": 550000,
  "rank": 1,
  "fetch_time": "2024-02-24 10:00:00"
}
```

**傳送測試訊息**
1. 點選 Topic 名稱
2. 點選 **Produce Message**
3. 輸入 JSON 格式的訊息
4. 點選 **Send**

範例：
```json
{
  "game_id": 999,
  "game_name": "Test Game",
  "current_players": 100,
  "peak_today": 200,
  "rank": 100,
  "fetch_time": "2024-02-24 12:00:00"
}
```

### 3. Consumer Groups 監控

**檢視 Consumer Groups**
- 點選左側選單 **Consumers**
- 可看到：
  - `clickhouse_steam_top_games_consumer`
  - `clickhouse_steam_game_details_consumer`

**檢視 Consumer 狀態**
- 點選 Consumer Group 名稱
- 可看到：
  - 訂閱的 Topics
  - 各 Partition 的 Offset
  - **Lag（延遲）**：重要指標！
    - Lag = 0：ClickHouse 已消費所有訊息
    - Lag > 0：ClickHouse 還有未消費的訊息

**Lag 監控範例**
```
Topic: steam_top_games_topic
Partition 0: Current Offset: 1000, Log End Offset: 1000, Lag: 0 ✓
Partition 1: Current Offset: 950,  Log End Offset: 1000, Lag: 50 ⚠️
Partition 2: Current Offset: 1000, Log End Offset: 1000, Lag: 0 ✓
```

### 4. Brokers 資訊

**檢視 Broker 狀態**
- 點選左側選單 **Brokers**
- 可看到：
  - Broker ID
  - 主機位址
  - 領導者 Partitions 數量
  - 資源使用率

---

## 實際操作範例

### 範例 1: 確認 Producer 有在傳送訊息

1. 開啟 Kafka UI：http://localhost:8080
2. 點選 **Topics** → **steam_top_games_topic**
3. 檢視 **Messages** 頁籤
4. 點選 **Fetch Messages**
5. 應該可以看到 Steam 遊戲資料的 JSON 訊息

### 範例 2: 檢查 ClickHouse 是否正常消費

1. 點選 **Consumers** → **clickhouse_steam_top_games_consumer**
2. 檢視各 Partition 的 **Lag**
3. 如果 Lag = 0，表示 ClickHouse 正常消費
4. 如果 Lag 持續增加，表示有問題需要檢查

### 範例 3: 手動傳送測試訊息

1. 點選 **Topics** → **steam_top_games_topic**
2. 點選 **Produce Message**
3. 貼上測試 JSON：
```json
{
  "game_id": 730,
  "game_name": "CS2 Test",
  "current_players": 999999,
  "peak_today": 999999,
  "rank": 1,
  "fetch_time": "2024-02-24 15:00:00"
}
```
4. 點選 **Send**
5. 到 ClickHouse 查詢，應該會看到這筆測試資料

```bash
docker exec clickhouse-server clickhouse-client --query \
  "SELECT * FROM steam_top_games WHERE game_name = 'CS2 Test' FORMAT Pretty"
```

### 範例 4: 監控資料流量

1. 點選 **Topics** → **steam_top_games_topic**
2. 檢視 **Overview** 頁籤
3. 觀察 **Messages per second**（每秒訊息數）
4. 觀察 **Bytes per second**（每秒位元組數）

---

## 常見問題

### 1. Kafka UI 無法連線到 Kafka

**症狀**: 開啟 http://localhost:8080 顯示錯誤

**解決方法**:
```bash
# 檢查 Kafka UI 日誌
docker logs kafka-ui

# 重啟 Kafka UI
docker-compose restart kafka-ui
```

### 2. 看不到 Topics

**症狀**: Topics 列表是空的

**原因**: Topics 尚未建立

**解決方法**:
```bash
# 手動建立 Topics（setup.sh 應該已經執行過）
docker exec kafka kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic steam_top_games_topic \
  --partitions 3 \
  --replication-factor 1
```

### 3. Consumer Lag 持續增加

**症狀**: Lag 一直增長，不減少

**可能原因**:
1. ClickHouse Kafka Engine 未啟動
2. ClickHouse 消費速度跟不上生產速度
3. ClickHouse 連線錯誤

**解決方法**:
```bash
# 檢查 ClickHouse 是否正常消費
docker exec clickhouse-server clickhouse-client --query \
  "SELECT * FROM kafka_steam_top_games LIMIT 5"

# 檢查 ClickHouse 日誌
docker logs clickhouse-server | grep -i kafka

# 增加 Kafka Consumers 數量（修改 Schema）
# ALTER TABLE kafka_steam_top_games MODIFY SETTING kafka_num_consumers = 3;
```

---

## Kafka UI vs Grafana

| 功能 | Kafka UI | Grafana |
|------|---------|---------|
| **用途** | 監控 Kafka | 視覺化資料分析 |
| **監控物件** | Topics, Messages, Consumers | ClickHouse 資料 |
| **即時性** | 即時 | 近即時（取決於查詢） |
| **訊息檢視** | ✅ 可以看原始訊息 | ❌ 只能看聚合資料 |
| **Consumer Lag** | ✅ 可以監控 | ❌ 需要自己寫查詢 |
| **資料分析** | ❌ 只能看原始資料 | ✅ 豐富的圖表 |
| **手動傳送訊息** | ✅ 支援 | ❌ 不支援 |

**建議使用情境**:
- 除錯 Kafka 問題 → **Kafka UI**
- 檢視訊息內容 → **Kafka UI**
- 監控 Consumer Lag → **Kafka UI**
- 分析遊戲趨勢 → **Grafana**
- 建立儀錶板 → **Grafana**

---

## 進階功能

### 1. 建立新 Topic

1. 點選 **Topics** → **Create Topic**
2. 輸入 Topic 名稱
3. 設定 Partitions 數量
4. 設定 Replication Factor
5. 點選 **Create**

### 2. 修改 Topic 設定

1. 點選 Topic 名稱
2. 點選 **Settings**
3. 可修改：
   - Retention Time（保留時間）
   - Segment Size（分段大小）
   - Compression Type（壓縮型別）

### 3. 刪除訊息

1. 點選 Topic 名稱
2. 點選 **Messages**
3. 選擇要刪除的訊息
4. 點選 **Delete**

**⚠️ 注意**: 刪除訊息是永久的！

---

## 快捷鍵

| 快捷鍵 | 功能 |
|--------|------|
| `Ctrl + K` | 全域搜尋 |
| `Ctrl + R` | 重新整理 |
| `Esc` | 關閉對話方塊 |

---

## 相關連結

- Kafka UI GitHub: https://github.com/provectus/kafka-ui
- 官方檔案: https://docs.kafka-ui.provectus.io/

---

## 更新服務清單

現在專案包含 4 個服務：

| 服務 | URL | 用途 |
|------|-----|------|
| **Kafka** | localhost:9092 | 訊息佇列 |
| **Kafka UI** | http://localhost:8080 | Kafka 管理介面 |
| **ClickHouse** | localhost:8123, 9000 | 時序資料庫 |
| **Grafana** | http://localhost:3000 | 資料視覺化 |

---

**專案作者**: 資深資料工程師
**最後更新**: 2024-02-24
