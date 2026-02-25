#!/bin/bash
# 假数据生成器启动脚本

set -e

echo "==========================================="
echo "假数据生成器启动脚本"
echo "==========================================="

# 建立日志目录
if [ ! -d "logs" ]; then
    echo "建立日志目录..."
    mkdir -p logs
fi

# 启动虚拟环境
if [ ! -d "venv" ]; then
    echo "建立 Python 虚拟环境..."
    python3 -m venv venv
fi

echo "启动虚拟环境..."
source venv/bin/activate

# 检查 Python 套件
echo "检查 Python 依赖套件..."
pip install -q -r requirements.txt
echo "✓ Python 套件已安装"

# 检查 Kafka 连线
echo "检查 Kafka 连线..."
if ! docker ps | grep -q kafka; then
    echo "❌ 错误: Kafka 容器未运行"
    echo "请先执行: docker-compose up -d"
    exit 1
fi
echo "✓ Kafka 连线正常"

# 检查 ClickHouse 连线
echo "检查 ClickHouse 连线..."
if ! docker ps | grep -q clickhouse; then
    echo "❌ 错误: ClickHouse 容器未运行"
    echo "请先执行: docker-compose up -d"
    exit 1
fi
echo "✓ ClickHouse 连线正常"

# 停止旧的 Producer 程序（包括真实和假数据的）
echo "清理旧的 Producer 程序..."
pkill -f steam_top_games_producer.py || true
pkill -f steam_game_details_producer.py || true
pkill -f fake_steam_top_games_producer.py || true
pkill -f fake_steam_game_details_producer.py || true
sleep 2

# 启动假数据生成器
echo ""
echo "==========================================="
echo "启动假数据生成器..."
echo "==========================================="

# 启动热门游戏假数据生成器
echo "启动假数据生成器 - 热门游戏统计..."
nohup python fake_steam_top_games_producer.py > logs/fake_top_games.log 2>&1 &
FAKE_TOP_GAMES_PID=$!
echo "✓ PID: $FAKE_TOP_GAMES_PID"
echo "  预估吞吐量: 50 条/秒"

sleep 2

# 启动游戏详情假数据生成器
echo "启动假数据生成器 - 游戏详细资讯..."
nohup python fake_steam_game_details_producer.py > logs/fake_game_details.log 2>&1 &
FAKE_GAME_DETAILS_PID=$!
echo "✓ PID: $FAKE_GAME_DETAILS_PID"
echo "  预估吞吐量: 10 条/秒"

echo ""
echo "==========================================="
echo "所有假数据生成器已启动"
echo "==========================================="
echo "热门游戏生成器 PID: $FAKE_TOP_GAMES_PID (50 条/秒)"
echo "游戏详情生成器 PID: $FAKE_GAME_DETAILS_PID (10 条/秒)"
echo ""
echo "总吞吐量: 约 60 条/秒 = 3600 条/分钟"
echo ""
echo "查看实时日志:"
echo "  tail -f logs/fake_top_games.log"
echo "  tail -f logs/fake_game_details.log"
echo ""
echo "监控 ClickHouse 数据增长:"
echo "  watch -n 1 'docker exec clickhouse-server clickhouse-client --query \"SELECT count() FROM steam_top_games\"'"
echo ""
echo "停止假数据生成器:"
echo "  ./stop_producers.sh"
echo "  或"
echo "  pkill -f fake_steam_top_games_producer.py"
echo "  pkill -f fake_steam_game_details_producer.py"
echo "==========================================="
