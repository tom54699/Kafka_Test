#!/bin/bash
# Steam 数据管线 Producers 停止脚本

echo "==========================================="
echo "停止 Steam 数据管线 Producers"
echo "==========================================="

# 查找并显示当前运行的 Producer
echo "当前运行的 Producers:"
ps aux | grep -E "(fake_)?steam_.*_producer.py" | grep -v grep || echo "  无运行中的 Producer"

echo ""
echo "正在停止所有 Producers..."

# 停止真实数据 Producers
pkill -f steam_top_games_producer.py 2>/dev/null || true
pkill -f steam_game_details_producer.py 2>/dev/null || true

# 停止假数据 Producers
pkill -f fake_steam_top_games_producer.py 2>/dev/null || true
pkill -f fake_steam_game_details_producer.py 2>/dev/null || true

sleep 2

# 确认是否已停止
if ps aux | grep -E "(fake_)?steam_.*_producer.py" | grep -v grep > /dev/null; then
    echo "❌ 部分 Producer 仍在运行，尝试强制终止..."
    pkill -9 -f steam_top_games_producer.py 2>/dev/null || true
    pkill -9 -f steam_game_details_producer.py 2>/dev/null || true
    pkill -9 -f fake_steam_top_games_producer.py 2>/dev/null || true
    pkill -9 -f fake_steam_game_details_producer.py 2>/dev/null || true
    sleep 1
fi

# 最终检查
if ps aux | grep -E "(fake_)?steam_.*_producer.py" | grep -v grep > /dev/null; then
    echo "❌ 错误: 无法停止所有 Producers"
    ps aux | grep -E "(fake_)?steam_.*_producer.py" | grep -v grep
    exit 1
else
    echo "✓ 所有 Producers 已停止"
fi

echo "==========================================="
