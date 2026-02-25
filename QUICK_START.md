# 快速啟動指南

## 一鍵啟動（推薦）

```bash
# 1. 執行自動設定腳本
./setup.sh

# 2. 啟動 Producers
./start_producers.sh

# 3. 查看日誌
tail -f logs/top_games.log
```

完成！專案已啟動。

---

## 驗證資料流

### 1. 查看 Kafka 訊息

```bash
docker exec kafka kafka-console-consumer \
  --topic steam_top_games_topic \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --max-messages 5
```

### 2. 查看 ClickHouse 資料

```bash
# 等待 1-2 分鐘後執行
docker exec clickhouse-server clickhouse-client --query \
  "SELECT count() FROM steam_top_games"

# 查看最新資料
docker exec clickhouse-server clickhouse-client --query \
  "SELECT * FROM steam_top_games ORDER BY fetch_time DESC LIMIT 10 FORMAT Pretty"
```

### 3. 開啟 Grafana

1. 瀏覽器訪問：http://localhost:3000
2. 登入帳號：`admin` / `admin`
3. 新增 ClickHouse Data Source
4. 建立 Dashboard（使用 `grafana_queries.sql` 中的查詢）

---

## 常用指令

### 啟動/停止

```bash
# 啟動 Producers
./start_producers.sh

# 停止 Producers
./stop_producers.sh

# 重啟 Docker 服務
docker-compose restart

# 停止所有服務
docker-compose down
```

### 查看日誌

```bash
# Producer 日誌
tail -f logs/top_games.log
tail -f logs/game_details.log

# Docker 容器日誌
docker logs kafka
docker logs clickhouse-server
docker logs grafana
```

### 清理資料

```bash
# 清理 ClickHouse 資料
docker exec clickhouse-server clickhouse-client --query \
  "TRUNCATE TABLE steam_top_games"

# 完全清理（包含 Docker volumes）
docker-compose down -v
```

---

## 故障排除

### Producer 無法啟動

```bash
# 檢查虛擬環境
source venv/bin/activate
pip list | grep kafka

# 重新安裝套件
pip install -r requirements.txt
```

### Kafka 連線失敗

```bash
# 檢查 Kafka 狀態
docker ps | grep kafka

# 重啟 Kafka
docker-compose restart kafka

# 查看 Kafka 日誌
docker logs kafka
```

### ClickHouse 無資料

```bash
# 檢查 Kafka Engine 是否消費
docker exec clickhouse-server clickhouse-client --query \
  "SELECT * FROM kafka_steam_top_games LIMIT 5"

# 檢查 Consumer Group
docker exec kafka kafka-consumer-groups --describe \
  --group clickhouse_steam_top_games_consumer \
  --bootstrap-server localhost:9092
```

---

## 服務資訊

| 服務 | URL | 帳號密碼 |
|------|-----|---------|
| Kafka | localhost:9092 | - |
| Kafka UI | http://localhost:8080 | 無需登入 |
| ClickHouse HTTP | localhost:8123 | - |
| ClickHouse Native | localhost:9000 | - |
| Grafana | http://localhost:3000 | admin / admin |

---

## 學習資源

- `README.md` - 完整專案說明
- `KAFKA_CLICKHOUSE_LEARNING_GUIDE.md` - 技術學習指南
- `ENV_SETUP_GUIDE.md` - 環境變數設定
- `grafana_queries.sql` - Grafana 查詢範例

---

**專案作者**: 資深數據工程師
**專案目標**: 學習 Kafka + ClickHouse 數據管線
