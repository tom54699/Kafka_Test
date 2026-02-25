#!/bin/bash
# Steam 資料管線 Producers 啟動指令碼

set -e

echo "==========================================="
echo "Steam 資料管線 Producers 啟動指令碼"
echo "==========================================="

# 建立日誌目錄
if [ ! -d "logs" ]; then
    echo "建立日誌目錄..."
    mkdir -p logs
fi

# 啟動虛擬環境
if [ ! -d "venv" ]; then
    echo "建立 Python 虛擬環境..."
    python3 -m venv venv
fi

echo "啟動虛擬環境..."
source venv/bin/activate

# 檢查 Python 套件
echo "檢查 Python 依賴套件..."
pip install -q -r requirements.txt
echo "✓ Python 套件已安裝"

# 檢查 Kafka 連線
echo "檢查 Kafka 連線..."
if ! docker ps | grep -q kafka; then
    echo "❌ 錯誤: Kafka 容器未執行"
    echo "請先執行: docker-compose up -d"
    exit 1
fi
echo "✓ Kafka 連線正常"

# 檢查 ClickHouse 連線
echo "檢查 ClickHouse 連線..."
if ! docker ps | grep -q clickhouse; then
    echo "❌ 錯誤: ClickHouse 容器未執行"
    echo "請先執行: docker-compose up -d"
    exit 1
fi
echo "✓ ClickHouse 連線正常"

# 停止舊的 Producer 程式
echo "清理舊的 Producer 程式..."
pkill -f steam_top_games_producer.py || true
pkill -f steam_game_details_producer.py || true
sleep 2

# 啟動 Producers
echo ""
echo "==========================================="
echo "啟動 Producers..."
echo "==========================================="

# 啟動熱門遊戲統計 Producer
echo "啟動 Steam 熱門遊戲統計 Producer..."
nohup python steam_top_games_producer.py > logs/top_games.log 2>&1 &
TOP_GAMES_PID=$!
echo "✓ PID: $TOP_GAMES_PID"

sleep 2

# 啟動遊戲詳細資訊 Producer
echo "啟動 Steam 遊戲詳細資訊 Producer..."
nohup python steam_game_details_producer.py > logs/game_details.log 2>&1 &
GAME_DETAILS_PID=$!
echo "✓ PID: $GAME_DETAILS_PID"

echo ""
echo "==========================================="
echo "所有 Producers 已啟動"
echo "==========================================="
echo "熱門遊戲 Producer PID: $TOP_GAMES_PID"
echo "遊戲詳情 Producer PID: $GAME_DETAILS_PID"
echo ""
echo "檢視日誌:"
echo "  tail -f logs/top_games.log"
echo "  tail -f logs/game_details.log"
echo ""
echo "停止 Producers:"
echo "  pkill -f steam_top_games_producer.py"
echo "  pkill -f steam_game_details_producer.py"
echo "==========================================="
