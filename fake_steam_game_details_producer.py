#!/usr/bin/env python3
"""
假資料生成器 - Steam 遊戲詳細資訊
功能：高頻生成符合 ClickHouse schema 的假資料，用於測試 Kafka 管線效能
"""

import json
import time
import logging
import random
from datetime import datetime, timedelta
from typing import List, Dict
from kafka import KafkaProducer
from kafka.errors import KafkaError

# ================== 設定 ==================
KAFKA_BOOTSTRAP_SERVERS = ['localhost:9092']
KAFKA_TOPIC = 'steam_game_details_topic'
SEND_INTERVAL = 0.1  # 每 0.1 秒傳送一批
BATCH_SIZE = 1000    # 每批傳送 1000 條資料（每秒 10000 條）

# 假遊戲資料池
FAKE_GAMES = [
    {"name": "Cyber Warriors 2077", "genres": ["Action", "RPG", "Sci-Fi"]},
    {"name": "Fantasy Quest Online", "genres": ["MMORPG", "Fantasy", "Adventure"]},
    {"name": "Space Explorer", "genres": ["Simulation", "Space", "Strategy"]},
    {"name": "Racing Master Pro", "genres": ["Racing", "Sports", "Simulation"]},
    {"name": "Horror Night", "genres": ["Horror", "Survival", "Indie"]},
    {"name": "Strategy Empire", "genres": ["Strategy", "War", "Historical"]},
    {"name": "Puzzle Mind", "genres": ["Puzzle", "Casual", "Indie"]},
    {"name": "Battle Royale X", "genres": ["Battle Royale", "Shooter", "Multiplayer"]},
    {"name": "City Builder Deluxe", "genres": ["Simulation", "City Building", "Management"]},
    {"name": "Adventure Island", "genres": ["Adventure", "Platform", "Action"]},
    {"name": "Zombie Survival", "genres": ["Survival", "Horror", "Action"]},
    {"name": "Medieval Kingdom", "genres": ["Strategy", "Medieval", "War"]},
    {"name": "Ocean Explorer", "genres": ["Simulation", "Underwater", "Adventure"]},
    {"name": "Sports Championship", "genres": ["Sports", "Simulation", "Multiplayer"]},
    {"name": "Cooking Master", "genres": ["Simulation", "Casual", "Family"]},
    {"name": "Detective Mystery", "genres": ["Adventure", "Mystery", "Puzzle"]},
    {"name": "Farm Life", "genres": ["Simulation", "Farming", "Casual"]},
    {"name": "Ninja Warriors", "genres": ["Action", "Fighting", "Indie"]},
    {"name": "Music Rhythm", "genres": ["Music", "Rhythm", "Casual"]},
    {"name": "Card Battle Arena", "genres": ["Card Game", "Strategy", "Multiplayer"]},
]

DEVELOPERS = [
    "Awesome Games Studio", "Dream Maker Inc", "Pixel Perfect Games",
    "Epic Gaming Corp", "Indie Devs United", "Creative Minds Studio",
    "Next Gen Entertainment", "Virtual Reality Labs", "Game Factory Ltd"
]

PUBLISHERS = [
    "Global Gaming Publishing", "Digital Dreams Publisher", "Mega Games Corp",
    "Indie Publisher Network", "AAA Entertainment", "Steam Direct"
]

# 日誌設定
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ================== Kafka Producer ==================
def create_kafka_producer() -> KafkaProducer:
    """建立 Kafka Producer"""
    try:
        producer = KafkaProducer(
            bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            acks='all',
            compression_type='gzip',
            batch_size=16384,
            linger_ms=10
        )
        logger.info("✓ Kafka Producer 連線成功")
        return producer
    except KafkaError as e:
        logger.error(f"✗ Kafka 連線失敗: {e}")
        raise

# ================== 假資料生成 ==================
def generate_fake_game_details(num_games: int) -> List[Dict]:
    """
    生成假的遊戲詳細資訊
    schema: game_id, game_name, short_description, release_date, developers,
            publishers, genres, original_price, discount_percent, final_price,
            positive_reviews, negative_reviews, total_reviews, review_score, fetch_time
    """
    fake_data = []
    fetch_time = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')

    for i in range(num_games):
        # 隨機選擇一個遊戲模板
        game_template = random.choice(FAKE_GAMES)
        game_name = game_template["name"]

        # 生成遊戲 ID
        game_id = 100000 + random.randint(1, 900000)

        # 生成釋出日期（過去 5 年內）
        days_ago = random.randint(0, 1825)
        release_date = (datetime.now() - timedelta(days=days_ago)).strftime('%Y-%m-%d')

        # 生成價格（可能有折扣）
        original_price = round(random.uniform(9.99, 59.99), 2)
        has_discount = random.random() < 0.3  # 30% 機率有折扣
        discount_percent = random.randint(10, 75) if has_discount else 0
        final_price = round(original_price * (1 - discount_percent / 100), 2)

        # 生成評價資料
        total_reviews = random.randint(100, 100000)
        review_score = round(random.uniform(60, 98), 2)
        positive_reviews = int(total_reviews * (review_score / 100))
        negative_reviews = total_reviews - positive_reviews

        # 隨機選擇開發商和發行商
        developers = random.sample(DEVELOPERS, random.randint(1, 2))
        publishers = random.sample(PUBLISHERS, random.randint(1, 2))

        game_record = {
            'game_id': game_id,
            'game_name': game_name,
            'short_description': f"An exciting {game_template['genres'][0].lower()} game with amazing gameplay and stunning graphics.",
            'release_date': release_date,
            'developers': developers,
            'publishers': publishers,
            'genres': game_template['genres'],
            'original_price': original_price,
            'discount_percent': discount_percent,
            'final_price': final_price,
            'positive_reviews': positive_reviews,
            'negative_reviews': negative_reviews,
            'total_reviews': total_reviews,
            'review_score': review_score,
            'fetch_time': fetch_time
        }

        fake_data.append(game_record)

    return fake_data

# ================== 傳送到 Kafka ==================
def send_batch_to_kafka(producer: KafkaProducer, data: List[Dict]) -> int:
    """批次傳送資料到 Kafka"""
    success_count = 0

    for record in data:
        try:
            producer.send(KAFKA_TOPIC, value=record)
            success_count += 1
        except Exception as e:
            logger.error(f"傳送失敗: {e}")

    producer.flush()
    return success_count

# ================== 主程式 ==================
def main():
    """主執行流程"""
    logger.info("=== 假資料生成器啟動（遊戲詳情）===")
    logger.info(f"配置: 每 {SEND_INTERVAL} 秒傳送 {BATCH_SIZE} 條資料")
    logger.info(f"預估吞吐量: {BATCH_SIZE / SEND_INTERVAL:.1f} 條/秒")
    logger.info("=" * 60)

    producer = create_kafka_producer()

    try:
        total_sent = 0
        iteration = 0

        while True:
            iteration += 1
            start_time = time.time()

            # 1. 生成假資料
            fake_data = generate_fake_game_details(BATCH_SIZE)

            # 2. 傳送到 Kafka
            success_count = send_batch_to_kafka(producer, fake_data)
            total_sent += success_count

            elapsed = time.time() - start_time

            # 3. 顯示統計
            if iteration % 5 == 0:  # 每 5 批顯示一次
                logger.info(
                    f"批次 #{iteration} | "
                    f"本批: {success_count} 條 | "
                    f"累計: {total_sent} 條 | "
                    f"耗時: {elapsed:.2f}s | "
                    f"速率: {success_count/elapsed:.1f} 條/秒"
                )

            # 4. 等待下次傳送
            sleep_time = max(0, SEND_INTERVAL - elapsed)
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        logger.info("\n收到中斷訊號，正在關閉...")
    except Exception as e:
        logger.error(f"程式錯誤: {e}")
    finally:
        producer.close()
        logger.info(f"已傳送總計 {total_sent} 條資料")
        logger.info("=== 假資料生成器已停止 ===")

if __name__ == "__main__":
    main()
