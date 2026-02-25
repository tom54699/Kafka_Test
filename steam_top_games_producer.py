#!/usr/bin/env python3
"""
Steam 熱門遊戲玩家統計 Producer
功能：定期抓取 Steam 熱門遊戲的即時玩家數，並發送到 Kafka
資料來源：Steam Charts API + Steam Web API
"""

import json
import time
import logging
from datetime import datetime
from typing import List, Dict, Optional, Any
import requests
from kafka import KafkaProducer
from kafka.errors import KafkaError

# ================== 設定 ==================
KAFKA_BOOTSTRAP_SERVERS = ['localhost:9092']
KAFKA_TOPIC = 'steam_top_games_topic'
FETCH_INTERVAL = 600  # 10 分鐘
TOP_GAMES_COUNT = 100  # 抓取前 100 名遊戲

# Steam API URLs
STEAM_CHARTS_API_URL = "https://api.steampowered.com/ISteamChartsService/GetMostPlayedGames/v1/"
STEAM_PLAYER_COUNT_API = "https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/"
HTTP_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) SteamKafkaProducer/1.0",
    "Accept": "application/json,text/plain,*/*",
}
STEAM_CHARTS_MAX_RETRIES = 3

# 日誌設定
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ================== Kafka Producer 初始化 ==================
def create_kafka_producer(max_retries=5) -> Optional[KafkaProducer]:
    """建立 Kafka Producer 連線，具備重試機制"""
    for attempt in range(max_retries):
        try:
            producer = KafkaProducer(
                bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                acks='all',  # 確保資料寫入成功
                retries=3,
                max_in_flight_requests_per_connection=1
            )
            logger.info("Kafka Producer 連線成功")
            return producer
        except KafkaError as e:
            logger.error(f"Kafka 連線失敗 (嘗試 {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                time.sleep(5)
            else:
                logger.critical("無法連接到 Kafka，程式終止")
                return None
    return None

def fetch_top_games_from_steam_charts() -> Dict[str, Dict[str, Any]]:
    """使用 Steam 官方 MostPlayedGames API。"""
    for attempt in range(1, STEAM_CHARTS_MAX_RETRIES + 1):
        try:
            response = requests.get(
                STEAM_CHARTS_API_URL,
                headers=HTTP_HEADERS,
                timeout=20
            )
            response.raise_for_status()

            data = response.json()
            ranks = data.get("response", {}).get("ranks", [])
            if not isinstance(ranks, list) or not ranks:
                logger.error("Steam Charts API 回應缺少 ranks 資料")
                return {}

            games_data: Dict[str, Dict[str, Any]] = {}
            max_rank = min(len(ranks), TOP_GAMES_COUNT)

            for item in ranks[:TOP_GAMES_COUNT]:
                app_id = str(item.get("appid", "")).strip()
                if not app_id.isdigit():
                    continue

                rank = int(item.get("rank", max_rank))
                peak_in_game = int(item.get("peak_in_game", 0))
                games_data[app_id] = {
                    "name": f"App {app_id}",  # 官方 endpoint 不提供名稱
                    "players_forever": max(max_rank - rank + 1, 0),
                    "ccu": peak_in_game
                }

            logger.info("成功從 Steam Charts 取得 %s 款遊戲", len(games_data))
            return games_data

        except requests.exceptions.RequestException as e:
            logger.warning(
                "Steam Charts API 請求失敗 (嘗試 %s/%s): %s",
                attempt,
                STEAM_CHARTS_MAX_RETRIES,
                e,
            )
        except requests.exceptions.JSONDecodeError as e:
            logger.warning(
                "Steam Charts API JSON 解析失敗 (嘗試 %s/%s): %s",
                attempt,
                STEAM_CHARTS_MAX_RETRIES,
                e,
            )

        if attempt < STEAM_CHARTS_MAX_RETRIES:
            backoff = 2 ** (attempt - 1)
            logger.info("等待 %s 秒後重試 Steam Charts API", backoff)
            time.sleep(backoff)

    logger.error("無法從 Steam Charts 取得熱門遊戲")
    return {}


def fetch_top_games() -> Dict[str, Dict[str, Any]]:
    """
    抓取熱門遊戲列表（Steam 官方 MostPlayedGames API）
    回傳格式：[{app_id, name, current_players, ...}, ...]
    """
    logger.info("開始抓取 Steam 熱門遊戲列表...")
    return fetch_top_games_from_steam_charts()

def fetch_current_players(app_id: int) -> Optional[int]:
    """
    從 Steam Web API 抓取特定遊戲的即時玩家數
    """
    try:
        params = {'appid': app_id}
        response = requests.get(
            STEAM_PLAYER_COUNT_API,
            params=params,
            timeout=10
        )
        response.raise_for_status()

        data = response.json()
        if data.get('response', {}).get('result') == 1:
            return data['response'].get('player_count', 0)
        return None

    except Exception as e:
        logger.warning(f"無法獲取遊戲 {app_id} 的玩家數: {e}")
        return None

def process_game_data(games_data: Dict[str, Dict[str, Any]]) -> List[Dict]:
    """
    處理遊戲資料，格式化為 Kafka 訊息格式
    並即時抓取每款遊戲的當前玩家數
    """
    processed_games = []
    # 使用 UTC，避免 Grafana/ClickHouse 時區錯位造成查不到資料
    fetch_time = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')

    # 回傳字典的 key 為 app_id
    sorted_games = sorted(
        games_data.items(),
        key=lambda x: x[1].get('players_forever', 0),
        reverse=True
    )[:TOP_GAMES_COUNT]

    logger.info(f"開始處理 {len(sorted_games)} 款遊戲的即時玩家數...")

    for rank, (app_id, game_info) in enumerate(sorted_games, 1):
        try:
            # 獲取即時玩家數
            current_players = fetch_current_players(int(app_id))

            # 如果無法獲取即時玩家數，使用排行榜的峰值資料
            if current_players is None:
                current_players = game_info.get('ccu', 0)

            game_record = {
                'game_id': int(app_id),
                'game_name': game_info.get('name', f'App {app_id}'),
                'current_players': current_players,
                'peak_today': game_info.get('ccu', 0),
                'rank': rank,
                'fetch_time': fetch_time
            }

            processed_games.append(game_record)

            # 避免 API Rate Limit
            if rank % 10 == 0:
                logger.info(f"已處理 {rank}/{len(sorted_games)} 款遊戲")
                time.sleep(1)  # 每 10 個請求休息 1 秒

        except Exception as e:
            logger.error(f"處理遊戲 {app_id} 時發生錯誤: {e}")
            continue

    logger.info(f"完成處理，共 {len(processed_games)} 筆記錄")
    return processed_games

# ================== 發送到 Kafka ==================
def send_to_kafka(producer: KafkaProducer, data: List[Dict]) -> int:
    """
    批次發送資料到 Kafka
    回傳成功發送的筆數
    """
    success_count = 0

    for record in data:
        try:
            future = producer.send(KAFKA_TOPIC, value=record)
            # 等待發送結果（同步模式）
            record_metadata = future.get(timeout=10)
            success_count += 1

            # 每 20 筆顯示一次進度
            if success_count % 20 == 0:
                logger.info(f"已發送 {success_count}/{len(data)} 筆資料到 Kafka")

        except KafkaError as e:
            logger.error(f"發送失敗 - 遊戲: {record.get('game_name')}, 錯誤: {e}")
        except Exception as e:
            logger.error(f"發送時發生未預期錯誤: {e}")

    # 確保所有訊息都已發送
    producer.flush()
    logger.info(f"批次發送完成，成功 {success_count}/{len(data)} 筆")

    return success_count

# ================== 主程式 ==================
def main():
    """主執行流程"""
    logger.info("=== Steam 熱門遊戲 Producer 啟動 ===")

    # 建立 Kafka Producer
    producer = create_kafka_producer()
    if not producer:
        return

    try:
        iteration = 0
        while True:
            iteration += 1
            logger.info(f"\n{'='*60}")
            logger.info(f"第 {iteration} 次資料抓取與發送")
            logger.info(f"{'='*60}")

            # 1. 抓取熱門遊戲列表
            games_data = fetch_top_games()

            if not games_data:
                logger.warning("未抓取到任何遊戲資料，跳過此次循環")
                time.sleep(FETCH_INTERVAL)
                continue

            # 2. 處理並獲取即時玩家數
            processed_data = process_game_data(games_data)

            if not processed_data:
                logger.warning("資料處理後無有效記錄，跳過此次循環")
                time.sleep(FETCH_INTERVAL)
                continue

            # 3. 發送到 Kafka
            success_count = send_to_kafka(producer, processed_data)

            logger.info(f"本次循環完成，成功發送 {success_count} 筆資料")
            logger.info(f"等待 {FETCH_INTERVAL} 秒後進行下次抓取...\n")

            # 休眠等待下次執行
            time.sleep(FETCH_INTERVAL)

    except KeyboardInterrupt:
        logger.info("\n收到中斷信號，正在關閉...")
    except Exception as e:
        logger.critical(f"程式發生嚴重錯誤: {e}")
    finally:
        if producer:
            producer.close()
            logger.info("Kafka Producer 已關閉")
        logger.info("=== Steam 熱門遊戲 Producer 已停止 ===")

if __name__ == "__main__":
    main()
