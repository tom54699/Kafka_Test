#!/bin/bash
# 假資料生成器啟動指令碼

set -e

echo "==========================================="
echo "假資料生成器啟動指令碼"
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

# 停止舊的 Producer 程式（包括真實和假資料的）
echo "清理舊的 Producer 程式..."
pkill -f steam_top_games_producer.py || true
pkill -f steam_game_details_producer.py || true
pkill -f fake_steam_top_games_producer.py || true
pkill -f fake_steam_game_details_producer.py || true
sleep 2

# 啟動假資料生成器
echo ""
echo "==========================================="
echo "啟動假資料生成器..."
echo "==========================================="

# 啟動熱門遊戲假資料生成器
echo "啟動假資料生成器 - 熱門遊戲統計..."
nohup python fake_steam_top_games_producer.py > logs/fake_top_games.log 2>&1 &
FAKE_TOP_GAMES_PID=$!
echo "✓ PID: $FAKE_TOP_GAMES_PID"
echo "  預估吞吐量: 20,000 條/秒"

sleep 2

# 啟動遊戲詳情假資料生成器
echo "啟動假資料生成器 - 遊戲詳細資訊..."
nohup python fake_steam_game_details_producer.py > logs/fake_game_details.log 2>&1 &
FAKE_GAME_DETAILS_PID=$!
echo "✓ PID: $FAKE_GAME_DETAILS_PID"
echo "  預估吞吐量: 10,000 條/秒"

echo ""
echo "==========================================="
echo "所有假資料生成器已啟動"
echo "==========================================="
echo "熱門遊戲生成器 PID: $FAKE_TOP_GAMES_PID (20,000 條/秒)"
echo "遊戲詳情生成器 PID: $FAKE_GAME_DETAILS_PID (10,000 條/秒)"
echo ""
echo "總吞吐量: 約 30,000 條/秒 = 1,800,000 條/分鐘"
echo ""
echo "檢視即時日誌:"
echo "  tail -f logs/fake_top_games.log"
echo "  tail -f logs/fake_game_details.log"
echo ""
echo "監控 ClickHouse 資料增長:"
echo "  watch -n 1 'docker exec clickhouse-server clickhouse-client --query \"SELECT count() FROM steam_top_games\"'"
echo ""
echo "停止假資料生成器:"
echo "  ./stop_producers.sh"
echo "  或"
echo "  pkill -f fake_steam_top_games_producer.py"
echo "  pkill -f fake_steam_game_details_producer.py"
echo "==========================================="
