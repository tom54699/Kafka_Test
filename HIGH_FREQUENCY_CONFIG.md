# 高頻率數據抓取配置方案

## 方案一：提高更新頻率（學習推薦）

適合本地學習、短期運行（1-2 天），資料量增加 10-20 倍。

### 修改配置

編輯 `.env` 檔案：

```env
# 原始設定（保守）
TOP_GAMES_FETCH_INTERVAL=600      # 10 分鐘
GAME_DETAILS_FETCH_INTERVAL=3600  # 1 小時

# 高頻率設定（學習用）
TOP_GAMES_FETCH_INTERVAL=60       # 1 分鐘
GAME_DETAILS_FETCH_INTERVAL=300   # 5 分鐘

# 增加抓取數量
TOP_GAMES_COUNT=200               # 增加到 200 款遊戲

# 降低 Rate Limit 延遲（風險：可能被限制）
API_REQUEST_DELAY=1.0             # 從 1.5 秒降到 1 秒
```

### 資料量對比

| 設定 | 每小時筆數 | 每天筆數 | 說明 |
|------|-----------|---------|------|
| **原始** | 700 | 16,800 | 保守安全 |
| **高頻** | 14,400 | 345,600 | **20 倍資料量** |

### 優點
- ✅ 資料量大增，更能體驗 Kafka 高吞吐
- ✅ 更接近真實生產環境的即時性
- ✅ ClickHouse 查詢更有感

### 風險
- ⚠️ 可能觸發 Steam API Rate Limit
- ⚠️ CPU 和網路使用率增加
- ⚠️ 不適合長期運行（建議 1-2 天內測試完畢）

---

## 方案二：模擬高頻數據（零風險）

不依賴真實 API，用模擬資料產生大量訊息。

### 建立模擬 Producer

```python
#!/usr/bin/env python3
"""
steam_mock_producer.py - 模擬高頻數據 Producer
用途：產生大量模擬資料，學習 Kafka 高吞吐能力
"""

import json
import time
import random
from datetime import datetime
from kafka import KafkaProducer

# 模擬遊戲列表
MOCK_GAMES = [
    {"id": 730, "name": "Counter-Strike 2"},
    {"id": 570, "name": "Dota 2"},
    {"id": 1938090, "name": "Call of Duty"},
    {"id": 271590, "name": "Grand Theft Auto V"},
    {"id": 1086940, "name": "Baldur's Gate 3"},
    {"id": 2358720, "name": "Black Myth: Wukong"},
    {"id": 2778580, "name": "Manor Lords"},
    {"id": 1245620, "name": "Elden Ring"},
    {"id": 1172470, "name": "Apex Legends"},
    {"id": 252490, "name": "Rust"},
]

producer = KafkaProducer(
    bootstrap_servers=['localhost:9092'],
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

def generate_mock_data():
    """產生模擬遊戲資料"""
    data = []
    for rank, game in enumerate(MOCK_GAMES, 1):
        # 模擬玩家數變化（加入隨機波動）
        base_players = 1000000 // rank
        variance = random.randint(-10000, 10000)

        record = {
            'game_id': game['id'],
            'game_name': game['name'],
            'current_players': max(0, base_players + variance),
            'peak_today': base_players + random.randint(0, 50000),
            'rank': rank,
            'fetch_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }
        data.append(record)
    return data

def main():
    print("🚀 啟動模擬 Producer（每 5 秒產生 100 筆資料）")
    iteration = 0

    while True:
        iteration += 1
        # 產生 100 筆模擬資料
        mock_data = generate_mock_data() * 10  # 100 筆

        for record in mock_data:
            producer.send('steam_top_games_topic', value=record)

        producer.flush()
        print(f"✓ 第 {iteration} 次發送完成，已發送 {len(mock_data)} 筆資料")

        time.sleep(5)  # 每 5 秒執行一次

if __name__ == "__main__":
    main()
```

### 資料量

- **頻率**: 每 5 秒
- **每次**: 100 筆
- **每小時**: 72,000 筆
- **每天**: 1,728,000 筆（**100 倍資料量！**）

### 優點
- ✅ **零 API 限制風險**
- ✅ 完全控制資料量和頻率
- ✅ 可以模擬各種情境（高峰、離峰、異常）
- ✅ 適合學習和壓力測試

### 缺點
- ❌ 非真實資料
- ❌ 無法展示 API 整合能力

---

## 方案三：多資料來源混合（生產推薦）

結合真實 API + 模擬資料，平衡真實性與資料量。

### 架構

```
┌─────────────────┐      ┌─────────────────┐
│  Real Steam API │      │  Mock Generator │
│  (每 10 分鐘)    │      │  (每 5 秒)       │
└────────┬────────┘      └────────┬────────┘
         │                        │
         ▼                        ▼
    ┌────────────────────────────────┐
    │          Kafka Topic           │
    └────────────────────────────────┘
```

### 實作

```python
#!/usr/bin/env python3
"""
hybrid_producer.py - 混合 Producer
每 10 分鐘抓真實資料 + 每 5 秒產生模擬資料
"""

import threading
import time
from steam_top_games_producer import fetch_and_send_real_data
from steam_mock_producer import generate_and_send_mock_data

def real_data_worker():
    """真實資料執行緒（每 10 分鐘）"""
    while True:
        fetch_and_send_real_data()
        time.sleep(600)

def mock_data_worker():
    """模擬資料執行緒（每 5 秒）"""
    while True:
        generate_and_send_mock_data()
        time.sleep(5)

if __name__ == "__main__":
    # 啟動兩個執行緒
    real_thread = threading.Thread(target=real_data_worker, daemon=True)
    mock_thread = threading.Thread(target=mock_data_worker, daemon=True)

    real_thread.start()
    mock_thread.start()

    # 保持主程式運行
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n停止 Hybrid Producer")
```

### 資料量

- **真實資料**: 600 筆/小時
- **模擬資料**: 72,000 筆/小時
- **總計**: 72,600 筆/小時（**100+ 倍資料量**）

---

## 方案四：追蹤所有遊戲（極限方案）

Steam 平台有超過 70,000 款遊戲，追蹤全部！

### 修改配置

```env
# 追蹤所有遊戲
TOP_GAMES_COUNT=5000              # 前 5000 款遊戲

# 批次處理
BATCH_SIZE=100                    # 每批處理 100 款
BATCH_INTERVAL=60                 # 每分鐘處理一批
```

### 資料量

- **每批**: 100 筆
- **每小時**: 6,000 筆
- **每天**: 144,000 筆（**8 倍資料量**）

### 風險
- ⚠️ **非常容易觸發 Rate Limit**
- ⚠️ 需要多個 API Key 輪替
- ⚠️ 需要更多資源（CPU、記憶體、磁碟）

---

## 推薦方案總結

| 方案 | 資料量倍數 | API 風險 | 適合場景 |
|------|-----------|---------|---------|
| **方案一：高頻率** | 20x | ⚠️ 中等 | 短期學習（1-2 天） |
| **方案二：模擬數據** | 100x | ✅ 無 | **學習 Kafka 推薦** |
| **方案三：混合** | 100x | ⚠️ 低 | **最佳平衡** |
| **方案四：全量追蹤** | 8x | ❌ 高 | 生產環境（需多 Key） |

---

## 立即開始：快速修改指令

### 方案一：高頻率（最簡單）

```bash
# 1. 修改 .env
nano .env

# 修改這兩行：
# TOP_GAMES_FETCH_INTERVAL=60
# GAME_DETAILS_FETCH_INTERVAL=300

# 2. 重啟 Producers
./stop_producers.sh
./start_producers.sh

# 3. 觀察資料流
tail -f logs/top_games.log
```

### 方案二：模擬數據（推薦）

已為你建立 `steam_mock_producer.py`，立即執行：

```bash
# 1. 啟動模擬 Producer
python steam_mock_producer.py

# 2. 另開終端查看 Kafka
docker exec kafka kafka-console-consumer \
  --topic steam_top_games_topic \
  --bootstrap-server localhost:9092

# 3. 查看 ClickHouse 資料量
docker exec clickhouse-server clickhouse-client --query \
  "SELECT count() FROM steam_top_games"
```

---

## 監控資料流量

### Kafka 吞吐量

```bash
# 查看 Topic 訊息數
docker exec kafka kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 \
  --topic steam_top_games_topic

# 查看 Consumer Lag
docker exec kafka kafka-consumer-groups --describe \
  --group clickhouse_steam_top_games_consumer \
  --bootstrap-server localhost:9092
```

### ClickHouse 寫入速度

```sql
-- 查看每分鐘寫入筆數
SELECT
    toStartOfMinute(fetch_time) as minute,
    count() as records
FROM steam_top_games
WHERE fetch_time >= now() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute DESC;
```

---

## 我的建議

對於**學習 Kafka + ClickHouse**：

1. **第一天**: 使用**方案二（模擬數據）**
   - 產生大量資料，體驗高吞吐
   - 測試 ClickHouse 查詢效能
   - 學習 Kafka 的平行處理

2. **第二天**: 使用**方案三（混合）**
   - 保留真實 API 整合
   - 加入模擬資料增加量
   - 更貼近生產環境

3. **第三天**: 使用**方案一（高頻率）**
   - 測試真實 API 的限制
   - 學習錯誤處理和重試機制
   - 了解 Rate Limit 的影響

這樣你可以在**3 天內完整體驗**從模擬到真實的完整數據管線！
