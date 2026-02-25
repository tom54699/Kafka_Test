#!/bin/bash
# Steam 數據管線專案快速設定腳本

set -e

echo "==========================================="
echo "Steam 數據管線專案快速設定"
echo "==========================================="

# 顏色定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 步驟 1: 檢查 Docker
echo -e "\n${YELLOW}[1/6] 檢查 Docker 環境...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ 錯誤: 未安裝 Docker${NC}"
    echo "請先安裝 Docker: https://docs.docker.com/get-docker/"
    exit 1
fi
echo -e "${GREEN}✓ Docker 已安裝${NC}"

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}❌ 錯誤: 未安裝 Docker Compose${NC}"
    echo "請先安裝 Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi
echo -e "${GREEN}✓ Docker Compose 已安裝${NC}"

# 步驟 2: 啟動基礎設施
echo -e "\n${YELLOW}[2/6] 啟動 Kafka + ClickHouse + Grafana...${NC}"
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}❌ 錯誤: 找不到 docker-compose.yml${NC}"
    exit 1
fi

docker-compose up -d
echo -e "${GREEN}✓ 基礎設施已啟動${NC}"

# 等待服務就緒
echo "等待服務啟動..."
sleep 10

# 步驟 3: 建立 Kafka Topics
echo -e "\n${YELLOW}[3/6] 建立 Kafka Topics...${NC}"

# 檢查 Topic 是否已存在
if docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 | grep -q "steam_top_games_topic"; then
    echo "Topic steam_top_games_topic 已存在，跳過建立"
else
    docker exec kafka kafka-topics --create \
        --bootstrap-server localhost:9092 \
        --topic steam_top_games_topic \
        --partitions 3 \
        --replication-factor 1
    echo -e "${GREEN}✓ 已建立 steam_top_games_topic${NC}"
fi

if docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 | grep -q "steam_game_details_topic"; then
    echo "Topic steam_game_details_topic 已存在，跳過建立"
else
    docker exec kafka kafka-topics --create \
        --bootstrap-server localhost:9092 \
        --topic steam_game_details_topic \
        --partitions 3 \
        --replication-factor 1
    echo -e "${GREEN}✓ 已建立 steam_game_details_topic${NC}"
fi

# 步驟 4: 建立 ClickHouse Schema
echo -e "\n${YELLOW}[4/6] 建立 ClickHouse Schema...${NC}"

if [ ! -f "clickhouse_schema.sql" ]; then
    echo -e "${RED}❌ 錯誤: 找不到 clickhouse_schema.sql${NC}"
    exit 1
fi

# 等待 ClickHouse 完全啟動
echo "等待 ClickHouse 完全啟動..."
sleep 5

# 執行 SQL 腳本
cat clickhouse_schema.sql | docker exec -i clickhouse-server clickhouse-client --multiquery

# 驗證資料表
echo "驗證資料表..."
TABLES=$(docker exec clickhouse-server clickhouse-client --query "SHOW TABLES" | wc -l)
if [ "$TABLES" -ge 6 ]; then
    echo -e "${GREEN}✓ ClickHouse Schema 建立成功 (共 $TABLES 個表)${NC}"
else
    echo -e "${RED}❌ 警告: 資料表數量不正確 (預期 6 個，實際 $TABLES 個)${NC}"
fi

# 步驟 5: 安裝 Python 依賴
echo -e "\n${YELLOW}[5/6] 安裝 Python 依賴套件...${NC}"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ 錯誤: 未安裝 Python 3${NC}"
    echo "請先安裝 Python 3: https://www.python.org/downloads/"
    exit 1
fi
echo -e "${GREEN}✓ Python 3 已安裝${NC}"

if [ ! -f "requirements.txt" ]; then
    echo -e "${RED}❌ 錯誤: 找不到 requirements.txt${NC}"
    exit 1
fi

# 建立虛擬環境
if [ ! -d "venv" ]; then
    echo "建立 Python 虛擬環境..."
    python3 -m venv venv
    echo -e "${GREEN}✓ 虛擬環境已建立${NC}"
else
    echo "虛擬環境已存在"
fi

# 啟動虛擬環境並安裝套件
echo "安裝 Python 套件到虛擬環境..."
source venv/bin/activate
pip install -q -r requirements.txt
deactivate
echo -e "${GREEN}✓ Python 套件安裝完成${NC}"

# 步驟 6: 建立日誌目錄
echo -e "\n${YELLOW}[6/6] 建立日誌目錄...${NC}"
mkdir -p logs
echo -e "${GREEN}✓ 日誌目錄已建立${NC}"

# 設定腳本執行權限
chmod +x start_producers.sh
chmod +x stop_producers.sh

# 完成
echo -e "\n==========================================="
echo -e "${GREEN}✓ 設定完成！${NC}"
echo "==========================================="
echo ""
echo "服務狀態:"
echo "  Kafka:          localhost:9092"
echo "  Kafka UI:       http://localhost:8080"
echo "  ClickHouse:     http://localhost:8123"
echo "  Grafana:        http://localhost:3000 (admin/admin)"
echo ""
echo -e "${YELLOW}下一步：${NC}"
echo "  1. 啟動 Producers:"
echo "     ./start_producers.sh"
echo ""
echo "  2. 停止 Producers:"
echo "     ./stop_producers.sh"
echo ""
echo "  3. 查看日誌:"
echo "     tail -f logs/top_games.log"
echo "     tail -f logs/game_details.log"
echo ""
echo "  4. 驗證資料:"
echo "     docker exec clickhouse-server clickhouse-client --query 'SELECT count() FROM steam_top_games'"
echo ""
echo "  5. 停止所有基礎設施:"
echo "     docker-compose down"
echo ""
echo "==========================================="
