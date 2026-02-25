# 環境變數設定指南

本專案使用 `.env` 檔案管理環境變數，包含 Steam API Key、Kafka 設定等敏感資訊。

## 快速開始

### 1. 建立 .env 檔案

```bash
# 複製範本檔案
cp .env.example .env

# 或手動建立
nano .env
```

### 2. 設定 Steam API Key

#### 取得 Steam Web API Key

1. 訪問 Steam Web API Key 註冊頁面：
   https://steamcommunity.com/dev/apikey

2. 登入你的 Steam 帳號

3. 填寫申請表單：
   - **Domain Name**: `localhost`（本地開發用）
   - **Agree to Terms**: 勾選同意條款

4. 提交後會獲得一組 API Key（32 位元的十六進位字串）
   範例：`388BF72F131CEF02BD0F2820C53A95C8`

5. 將 API Key 貼到 `.env` 檔案中：
   ```
   STEAM_API_KEY=你的API_KEY
   ```

#### 取得 Steam ID

1. 訪問 Steam ID 查詢工具：
   https://steamid.io/

2. 輸入你的 Steam Profile URL 或用戶名稱

3. 複製 **steamID64** 欄位的數字
   範例：`76561198138286305`

4. 將 Steam ID 貼到 `.env` 檔案中：
   ```
   STEAM_ID=你的STEAM_ID
   ```

### 3. 完整 .env 檔案範例

```env
# Steam API 設定
STEAM_API_KEY=388BF72F131CEF02BD0F2820C53A95C8
STEAM_ID=76561198138286305

# Kafka 設定
KAFKA_BOOTSTRAP_SERVERS=localhost:9092
KAFKA_TOP_GAMES_TOPIC=steam_top_games_topic
KAFKA_GAME_DETAILS_TOPIC=steam_game_details_topic

# ClickHouse 設定
CLICKHOUSE_HOST=localhost
CLICKHOUSE_HTTP_PORT=8123
CLICKHOUSE_NATIVE_PORT=9000
CLICKHOUSE_DATABASE=default

# Producer 執行設定
TOP_GAMES_FETCH_INTERVAL=600
GAME_DETAILS_FETCH_INTERVAL=3600
TOP_GAMES_COUNT=100

# API Rate Limit
API_REQUEST_DELAY=1.5
BATCH_DELAY=1.0
```

## 在 Python 中使用環境變數

### 基本用法

```python
import os
from dotenv import load_dotenv

# 載入 .env 檔案
load_dotenv()

# 讀取環境變數
STEAM_API_KEY = os.getenv('STEAM_API_KEY')
KAFKA_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')

# 數值型別需要轉換
FETCH_INTERVAL = int(os.getenv('TOP_GAMES_FETCH_INTERVAL', '600'))
```

### 完整範例

參考 `example_env_usage.py` 檔案：

```bash
# 執行範例程式
python example_env_usage.py

# 輸出：
# ============================================================
# 環境變數設定
# ============================================================
# Steam API Key: 388BF72F...
# Steam ID: 76561198138286305
# Kafka Servers: localhost:9092
# ...
# ✓ 所有必要的環境變數已設定
# ✓ Steam API 呼叫成功！
```

## 環境變數說明

### Steam API 相關

| 變數名稱 | 說明 | 必填 | 預設值 |
|---------|------|------|--------|
| `STEAM_API_KEY` | Steam Web API Key | ✅ | - |
| `STEAM_ID` | Steam 用戶 ID (SteamID64) | ❌ | - |

### Kafka 相關

| 變數名稱 | 說明 | 必填 | 預設值 |
|---------|------|------|--------|
| `KAFKA_BOOTSTRAP_SERVERS` | Kafka 伺服器位址 | ✅ | `localhost:9092` |
| `KAFKA_TOP_GAMES_TOPIC` | 熱門遊戲 Topic 名稱 | ❌ | `steam_top_games_topic` |
| `KAFKA_GAME_DETAILS_TOPIC` | 遊戲詳情 Topic 名稱 | ❌ | `steam_game_details_topic` |

### ClickHouse 相關

| 變數名稱 | 說明 | 必填 | 預設值 |
|---------|------|------|--------|
| `CLICKHOUSE_HOST` | ClickHouse 主機位址 | ❌ | `localhost` |
| `CLICKHOUSE_HTTP_PORT` | HTTP 介面埠號 | ❌ | `8123` |
| `CLICKHOUSE_NATIVE_PORT` | Native 介面埠號 | ❌ | `9000` |
| `CLICKHOUSE_DATABASE` | 資料庫名稱 | ❌ | `default` |

### Producer 執行設定

| 變數名稱 | 說明 | 必填 | 預設值 |
|---------|------|------|--------|
| `TOP_GAMES_FETCH_INTERVAL` | 熱門遊戲抓取間隔（秒） | ❌ | `600` |
| `GAME_DETAILS_FETCH_INTERVAL` | 遊戲詳情抓取間隔（秒） | ❌ | `3600` |
| `TOP_GAMES_COUNT` | 抓取遊戲數量 | ❌ | `100` |
| `API_REQUEST_DELAY` | API 請求延遲（秒） | ❌ | `1.5` |
| `BATCH_DELAY` | 批次處理延遲（秒） | ❌ | `1.0` |

## 安全性注意事項

### ⚠️ 不要將 .env 上傳到 Git

`.env` 檔案包含敏感資訊（API Key），**絕對不要上傳到 Git**！

已在 `.gitignore` 中加入：
```
.env
.env.local
```

### ✅ 使用 .env.example 作為範本

- `.env.example` 不包含真實資料，可以上傳到 Git
- 其他開發者可以複製 `.env.example` 並填入自己的設定

### 🔐 保護你的 API Key

1. **不要分享**: 不要將 API Key 分享給他人
2. **定期更換**: 定期重新產生新的 API Key
3. **限制權限**: 在 Steam API 設定中限制 Domain
4. **撤銷舊的 Key**: 如果 Key 洩漏，立即到 Steam 後台撤銷

**撤銷 API Key**:
1. 訪問 https://steamcommunity.com/dev/apikey
2. 點擊 "Revoke My Steam Web API Key"
3. 重新產生新的 Key

## 測試環境變數設定

### 方法 1: 使用範例程式

```bash
python example_env_usage.py
```

### 方法 2: 手動測試

```bash
# 安裝依賴
pip install python-dotenv requests

# 啟動 Python
python3

# 輸入以下程式碼
>>> from dotenv import load_dotenv
>>> import os
>>> load_dotenv()
True
>>> os.getenv('STEAM_API_KEY')
'388BF72F131CEF02BD0F2820C53A95C8'
>>> os.getenv('KAFKA_BOOTSTRAP_SERVERS')
'localhost:9092'
```

### 方法 3: 驗證 Steam API

```bash
# 使用 curl 測試 Steam API（替換成你的 API Key 和 Steam ID）
curl "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=YOUR_API_KEY&steamids=YOUR_STEAM_ID"

# 如果成功，會回傳 JSON 格式的玩家資料
```

## 疑難排解

### 問題 1: 找不到 .env 檔案

**錯誤訊息**: 環境變數為空或使用預設值

**解決方法**:
```bash
# 確認 .env 檔案存在
ls -la .env

# 如果不存在，複製範本
cp .env.example .env
```

### 問題 2: 環境變數未載入

**錯誤訊息**: `STEAM_API_KEY` 為 `None`

**解決方法**:
```python
# 確認 .env 檔案路徑
from dotenv import load_dotenv
load_dotenv('.env')  # 明確指定檔案路徑

# 或使用絕對路徑
import os
from pathlib import Path

env_path = Path('.') / '.env'
load_dotenv(dotenv_path=env_path)
```

### 問題 3: Steam API Key 無效

**錯誤訊息**: `403 Forbidden` 或 `Invalid API Key`

**解決方法**:
1. 確認 API Key 正確（32 位元十六進位字串）
2. 確認 Domain 設定為 `localhost`
3. 確認 API Key 未被撤銷
4. 重新產生新的 API Key

### 問題 4: Steam ID 格式錯誤

**錯誤訊息**: 無法獲取玩家資料

**解決方法**:
- 確認使用 **steamID64** 格式（17 位數字）
- 不要使用 Steam3 ID 或其他格式
- 使用 https://steamid.io/ 查詢正確的 ID

## 不同環境的設定

### 開發環境

```bash
# .env
STEAM_API_KEY=你的開發用KEY
KAFKA_BOOTSTRAP_SERVERS=localhost:9092
TOP_GAMES_FETCH_INTERVAL=600
```

### 生產環境

```bash
# .env.production
STEAM_API_KEY=你的生產用KEY
KAFKA_BOOTSTRAP_SERVERS=kafka-cluster:9092
TOP_GAMES_FETCH_INTERVAL=300  # 更頻繁的更新
```

### 使用不同環境的設定

```python
import os
from dotenv import load_dotenv

# 根據環境變數載入不同的 .env 檔案
env = os.getenv('ENVIRONMENT', 'development')

if env == 'production':
    load_dotenv('.env.production')
else:
    load_dotenv('.env')
```

## 常見 Steam API 用途

使用你的 API Key 可以存取以下 Steam API：

### 1. 玩家資訊
```python
# ISteamUser/GetPlayerSummaries
url = f"https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key={API_KEY}&steamids={STEAM_ID}"
```

### 2. 玩家遊戲庫存
```python
# IPlayerService/GetOwnedGames
url = f"https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key={API_KEY}&steamid={STEAM_ID}&include_appinfo=1"
```

### 3. 玩家最近遊戲
```python
# IPlayerService/GetRecentlyPlayedGames
url = f"https://api.steampowered.com/IPlayerService/GetRecentlyPlayedGames/v1/?key={API_KEY}&steamid={STEAM_ID}"
```

### 4. 遊戲成就
```python
# ISteamUserStats/GetPlayerAchievements
url = f"https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v1/?key={API_KEY}&steamid={STEAM_ID}&appid={GAME_ID}"
```

---

**相關資源**:
- Steam Web API 文件: https://steamcommunity.com/dev
- Steam ID 查詢: https://steamid.io/
- python-dotenv 文件: https://pypi.org/project/python-dotenv/
