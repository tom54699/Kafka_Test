#!/usr/bin/env python3
"""
Steam 遊戲詳細資訊 Producer
功能：定期抓取 Steam 遊戲的詳細資訊（價格、評價、開發商等），並發送到 Kafka
資料來源：Steam Store API
"""

import json
import time
import logging
from datetime import datetime
from typing import List, Dict, Optional
import requests
from kafka import KafkaProducer
from kafka.errors import KafkaError

# ================== 設定 ==================
KAFKA_BOOTSTRAP_SERVERS = ['localhost:9092']
KAFKA_TOPIC = 'steam_game_details_topic'
FETCH_INTERVAL = 3600  # 1 小時（遊戲資訊變動較慢）

# Steam Store API
STEAM_STORE_API_URL = "https://store.steampowered.com/api/appdetails"
STEAM_CHARTS_API_URL = "https://api.steampowered.com/ISteamChartsService/GetMostPlayedGames/v1/"
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
                acks='all',
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

# ================== 資料抓取函數 ==================
def fetch_top_game_ids(top_n=100) -> List[int]:
    """
    從 Steam 官方 API 抓取熱門遊戲的 AppID 列表
    """
    logger.info(f"正在獲取前 {top_n} 熱門遊戲的 AppID...")
    app_ids = fetch_top_game_ids_from_steam_charts(top_n)
    if app_ids:
        logger.info(f"成功從 Steam Charts 獲取 {len(app_ids)} 個遊戲 AppID")
        return app_ids

    logger.error("獲取遊戲 AppID 失敗（Steam Charts）")
    return []


def fetch_top_game_ids_from_steam_charts(top_n=100) -> List[int]:
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
                return []

            app_ids: List[int] = []
            for item in ranks[:top_n]:
                app_id = item.get("appid")
                if isinstance(app_id, int):
                    app_ids.append(app_id)
                elif isinstance(app_id, str) and app_id.isdigit():
                    app_ids.append(int(app_id))

            return app_ids

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

    return []

def fetch_game_details(app_id: int) -> Optional[Dict]:
    """
    從 Steam Store API 抓取遊戲詳細資訊
    """
    try:
        params = {
            'appids': app_id,
            'cc': 'tw',  # 台灣區域
            'l': 'tchinese'  # 繁體中文
        }

        response = requests.get(
            STEAM_STORE_API_URL,
            params=params,
            headers=HTTP_HEADERS,
            timeout=15
        )
        response.raise_for_status()

        data = response.json()

        # 檢查 API 回應
        if str(app_id) not in data:
            logger.warning(f"遊戲 {app_id} 不在 API 回應中")
            return None

        game_data = data[str(app_id)]

        if not game_data.get('success', False):
            logger.warning(f"遊戲 {app_id} 無法取得資料（可能為 DLC 或不可用）")
            return None

        return game_data.get('data', {})

    except requests.exceptions.Timeout:
        logger.warning(f"遊戲 {app_id} 請求逾時")
        return None
    except requests.exceptions.RequestException as e:
        logger.warning(f"遊戲 {app_id} 請求失敗: {e}")
        return None
    except Exception as e:
        logger.error(f"處理遊戲 {app_id} 時發生錯誤: {e}")
        return None

def process_game_details(app_id: int, game_data: Dict) -> Optional[Dict]:
    """
    處理遊戲詳細資料，格式化為 Kafka 訊息格式
    """
    try:
        # 使用 UTC，避免 Grafana/ClickHouse 時區錯位造成查不到資料
        fetch_time = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')

        # 處理價格資訊
        price_overview = game_data.get('price_overview', {})
        original_price = price_overview.get('initial', 0) / 100.0  # 轉換為元
        discount_percent = price_overview.get('discount_percent', 0)
        final_price = price_overview.get('final', 0) / 100.0

        # 如果遊戲是免費的
        if game_data.get('is_free', False):
            original_price = 0.0
            final_price = 0.0
            discount_percent = 0

        # 處理評價資訊
        recommendations = game_data.get('recommendations', {})
        total_reviews = recommendations.get('total', 0)

        # 計算評價分數（簡化版，實際可能需要更複雜的計算）
        positive_reviews = int(total_reviews * 0.8)  # Steam 不直接提供，這裡估算
        negative_reviews = total_reviews - positive_reviews
        review_score = (positive_reviews / total_reviews * 100) if total_reviews > 0 else 0.0

        # 處理類型資訊
        genres = [g.get('description', '') for g in game_data.get('genres', [])]

        # 處理開發商和發行商
        developers = game_data.get('developers', [])
        publishers = game_data.get('publishers', [])

        game_record = {
            'game_id': app_id,
            'game_name': game_data.get('name', 'Unknown'),
            'short_description': game_data.get('short_description', '')[:500],  # 限制長度
            'release_date': game_data.get('release_date', {}).get('date', ''),
            'developers': developers,
            'publishers': publishers,
            'genres': genres,
            'original_price': original_price,
            'discount_percent': discount_percent,
            'final_price': final_price,
            'positive_reviews': positive_reviews,
            'negative_reviews': negative_reviews,
            'total_reviews': total_reviews,
            'review_score': round(review_score, 2),
            'fetch_time': fetch_time
        }

        return game_record

    except Exception as e:
        logger.error(f"處理遊戲 {app_id} 的資料時發生錯誤: {e}")
        return None

# ================== 發送到 Kafka ==================
def send_to_kafka(producer: KafkaProducer, record: Dict) -> bool:
    """
    發送單筆資料到 Kafka
    """
    try:
        future = producer.send(KAFKA_TOPIC, value=record)
        future.get(timeout=10)
        return True
    except KafkaError as e:
        logger.error(f"發送失敗 - 遊戲: {record.get('game_name')}, 錯誤: {e}")
        return False
    except Exception as e:
        logger.error(f"發送時發生未預期錯誤: {e}")
        return False

# ================== 主程式 ==================
def main():
    """主執行流程"""
    logger.info("=== Steam 遊戲詳細資訊 Producer 啟動 ===")

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

            # 1. 獲取熱門遊戲的 AppID 列表
            app_ids = fetch_top_game_ids(top_n=100)

            if not app_ids:
                logger.warning("未獲取到任何遊戲 AppID，跳過此次循環")
                time.sleep(FETCH_INTERVAL)
                continue

            # 2. 逐一抓取遊戲詳細資訊並發送到 Kafka
            success_count = 0
            failed_count = 0

            for idx, app_id in enumerate(app_ids, 1):
                logger.info(f"處理中 ({idx}/{len(app_ids)}): AppID {app_id}")

                # 抓取遊戲詳細資訊
                game_data = fetch_game_details(app_id)

                if not game_data:
                    failed_count += 1
                    time.sleep(1.5)  # Rate Limit 保護
                    continue

                # 處理資料
                game_record = process_game_details(app_id, game_data)

                if not game_record:
                    failed_count += 1
                    time.sleep(1.5)
                    continue

                # 發送到 Kafka
                if send_to_kafka(producer, game_record):
                    success_count += 1
                    logger.info(f"✓ 成功發送: {game_record['game_name']}")
                else:
                    failed_count += 1

                # Rate Limit 控制：每個請求之間等待 1.5 秒
                # Steam Store API 有 Rate Limit，避免被封鎖
                time.sleep(1.5)

                # 每 10 筆顯示進度
                if idx % 10 == 0:
                    logger.info(f"進度: {idx}/{len(app_ids)}, 成功: {success_count}, 失敗: {failed_count}")

            # 確保所有訊息都已發送
            producer.flush()

            logger.info(f"\n{'='*60}")
            logger.info(f"本次循環完成統計:")
            logger.info(f"  總數: {len(app_ids)}")
            logger.info(f"  成功: {success_count}")
            logger.info(f"  失敗: {failed_count}")
            logger.info(f"  成功率: {success_count/len(app_ids)*100:.1f}%")
            logger.info(f"{'='*60}")
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
        logger.info("=== Steam 遊戲詳細資訊 Producer 已停止 ===")

if __name__ == "__main__":
    main()
