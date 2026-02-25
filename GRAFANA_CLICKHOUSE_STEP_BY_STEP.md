# Grafana ClickHouse 設定超詳細步驟

## ⚠️ 重要提示

Grafana 剛重新建立，你需要**重新登入**！

另外，請先確認 `docker-compose.yml` 的 ClickHouse 有設定：

```yaml
CLICKHOUSE_SKIP_USER_SETUP=1
```

這是新版 ClickHouse image 必要設定，否則 `default` 使用者會被禁止網路連線，Grafana 會一直出現 authentication failed。

## 步驟 1: 登入 Grafana

1. 開啟瀏覽器：http://localhost:3000
2. 帳號：`admin`
3. 密碼：`admin`
4. 如果要求修改密碼，點「Skip」跳過

---

## 步驟 2: 進入 Data Sources 頁面

1. 點選左側選單的 **齒輪圖示⚙️ (Configuration)**
   - 或點選左側選單 **三條線☰** → **Connections**

2. 點選 **Data sources**

3. 點選右上角藍色按鈕 **Add data source**

---

## 步驟 3: 選擇 ClickHouse

1. 在搜尋框輸入：`clickhouse`

2. 應該會看到 **ClickHouse** 卡片（圖示是綠色的資料庫圖案）

3. 點選 **ClickHouse**

---

## 步驟 4: 填寫設定（最關鍵！）

### 🔴 必填欄位（一定要填！）

#### Name
```
ClickHouse
```

#### Server

**注意：這裡有 3 個欄位，都要填！**

1. **Protocol**（下拉選單）
   ```
   選擇: http
   ```

2. **Host**（文字框）
   ```
   clickhouse
   ```
   ⚠️ 不要加 `http://`！只填 `clickhouse`

3. **Port**（數字框）
   ```
   8123
   ```

#### ClickHouse settings

1. **Default database**
   ```
   default
   ```

2. **Username**
   ```
   default
   ```

3. **Password**
   ```
   留空（完全不要輸入任何東西！）
   ```

---

### 🟡 可選欄位（可以留空）

以下欄位**全部留空或使用預設值**：

- ✅ Secure connection: 不勾選
- ✅ Skip TLS Verify: 不勾選
- ✅ TLS/SSL Auth Details: 全部留空
- ✅ Additional settings: 全部留空
- ✅ Logs: 不勾選
- ✅ Traces: 不勾選
- ✅ Query timeout: 留空
- ✅ Dial timeout: 留空

**重要：不要亂填其他欄位！**

---

## 步驟 5: 儲存並測試

1. 滾動到頁面**最底部**

2. 點選藍色按鈕：**Save & test**

3. 等待 2-3 秒

4. 應該會看到綠色訊息：
   ```
   ✅ Data source is working
   ```

---

## 🚨 如果還是失敗

### 錯誤訊息 1: "failed to create ClickHouse client"

**可能原因**：Host 填錯了

**檢查**：
- Host 欄位應該是：`clickhouse`（沒有 http://）
- 不是：`http://clickhouse`
- 不是：`localhost`
- 不是：`http://localhost:8123`

### 錯誤訊息 2: "invalid protocol"

**可能原因**：Protocol 選錯了

**檢查**：
- Protocol 應該選：`http`（小寫）
- 不是：`HTTP`
- 不是：`Native`
- 不是：`https`

### 錯誤訊息 3: "connection refused"

**可能原因**：ClickHouse 未執行

**解決方法**：
```bash
# 檢查 ClickHouse 狀態
docker ps | grep clickhouse

# 如果沒執行，重啟它
docker-compose restart clickhouse
```

### 錯誤訊息 4: "authentication failed"

**可能原因**：Password 填了東西

**解決方法**：
- Password 欄位必須**完全空白**
- 不要填任何東西，連空格都不要！

---

## 📸 設定範例截圖（文字版）

```
┌─────────────────────────────────────────────────┐
│ Settings                                        │
├─────────────────────────────────────────────────┤
│                                                 │
│ Name: ClickHouse                                │
│                                                 │
│ ━━━ Server ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│ Protocol: [http ▼]                              │
│ Host: clickhouse                                │
│ Port: 8123                                      │
│                                                 │
│ ━━━ ClickHouse settings ━━━━━━━━━━━━━━━━━━━━━  │
│ Default database: default                       │
│ Username: default                               │
│ Password: [留空]                                │
│                                                 │
│ ━━━ Additional settings ━━━━━━━━━━━━━━━━━━━━━  │
│ [全部留空或使用預設值]                          │
│                                                 │
│                                                 │
│                                                 │
│                       [Save & test] ← 點這裡    │
└─────────────────────────────────────────────────┘
```

---

## ✅ 設定成功後

### 驗證連線

1. 點選左側選單 **Explore**（放大鏡圖示🔍）

2. 上方選擇 Data source：**ClickHouse**

3. 在 Query 框輸入：
   ```sql
   SELECT 1
   ```

4. 點選右上角 **Run query**

5. 應該會看到結果：`1`

### 查詢實際資料

在 Query 框輸入：
```sql
SELECT count() FROM steam_top_games
```

應該會看到數字（例如：100、200 等），表示有資料！

---

## 📝 完整設定清單

複製這個表格，填寫時對照：

| 欄位 | 填寫內容 | 狀態 |
|------|---------|------|
| Name | `ClickHouse` | □ |
| Protocol | `http` (下拉選擇) | □ |
| Host | `clickhouse` | □ |
| Port | `8123` | □ |
| Default database | `default` | □ |
| Username | `default` | □ |
| Password | 留空 | □ |
| 其他所有欄位 | 留空 | □ |

---

## 🆘 最後手段

如果按照上述步驟還是失敗，執行以下指令並將輸出貼給我：

```bash
# 1. 檢查 ClickHouse 狀態
docker ps | grep clickhouse

# 2. 測試 ClickHouse 連線
docker exec clickhouse-server clickhouse-client --query "SELECT 1"

# 3. 從 Grafana 容器測試連線
docker exec grafana wget -O- http://clickhouse:8123/

# 4. 檢視 Grafana 日誌
docker logs grafana 2>&1 | tail -30
```

然後提供輸出結果以便進一步診斷。

---

**重點提醒**：
- ✅ Host 填 `clickhouse`（沒有 http://）
- ✅ Protocol 選 `http`（小寫）
- ✅ Port 填 `8123`
- ✅ Password **完全留空**
- ✅ 其他欄位全部留空

按照這個步驟，應該就能成功連線了！
