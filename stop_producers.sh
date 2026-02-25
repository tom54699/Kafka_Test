#!/bin/bash
# Steam 資料管線 Producers 停止指令碼

echo "==========================================="
echo "停止 Steam 資料管線 Producers"
echo "==========================================="

# 查詢並顯示當前執行的 Producer
echo "當前執行的 Producers:"
ps aux | grep -E "(fake_)?steam_.*_producer.py" | grep -v grep || echo "  無執行中的 Producer"

echo ""
echo "正在停止所有 Producers..."

# 停止真實資料 Producers
pkill -f steam_top_games_producer.py 2>/dev/null || true
pkill -f steam_game_details_producer.py 2>/dev/null || true

# 停止假資料 Producers
pkill -f fake_steam_top_games_producer.py 2>/dev/null || true
pkill -f fake_steam_game_details_producer.py 2>/dev/null || true

sleep 2

# 確認是否已停止
if ps aux | grep -E "(fake_)?steam_.*_producer.py" | grep -v grep > /dev/null; then
    echo "❌ 部分 Producer 仍在執行，嘗試強制終止..."
    pkill -9 -f steam_top_games_producer.py 2>/dev/null || true
    pkill -9 -f steam_game_details_producer.py 2>/dev/null || true
    pkill -9 -f fake_steam_top_games_producer.py 2>/dev/null || true
    pkill -9 -f fake_steam_game_details_producer.py 2>/dev/null || true
    sleep 1
fi

# 最終檢查
if ps aux | grep -E "(fake_)?steam_.*_producer.py" | grep -v grep > /dev/null; then
    echo "❌ 錯誤: 無法停止所有 Producers"
    ps aux | grep -E "(fake_)?steam_.*_producer.py" | grep -v grep
    exit 1
else
    echo "✓ 所有 Producers 已停止"
fi

echo "==========================================="
