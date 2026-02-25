#!/usr/bin/env python3
"""
假数据生成器 - Steam 热门游戏统计
功能：高频生成符合 ClickHouse schema 的假数据，用于测试 Kafka 管线性能
"""

import json
import time
import logging
import random
from datetime import datetime
from typing import List, Dict
from kafka import KafkaProducer
from kafka.errors import KafkaError

# ================== 设定 ==================
KAFKA_BOOTSTRAP_SERVERS = ['localhost:9092']
KAFKA_TOPIC = 'steam_top_games_topic'
SEND_INTERVAL = 0.05  # 每 0.05 秒发送一批
BATCH_SIZE = 1000     # 每批发送 1000 条数据（每秒 20000 条）

# 假游戏名称池
FAKE_GAME_NAMES = [
    "Counter-Strike: Global Offensive", "Dota 2", "PUBG: BATTLEGROUNDS",
    "Apex Legends", "Grand Theft Auto V", "Lost Ark", "Team Fortress 2",
    "Rust", "ARK: Survival Evolved", "Warframe", "Rainbow Six Siege",
    "Dead by Daylight", "Rocket League", "Path of Exile", "Destiny 2",
    "Terraria", "The Witcher 3", "Cyberpunk 2077", "Elden Ring",
    "Monster Hunter: World", "Valheim", "Among Us", "Fall Guys",
    "Stardew Valley", "Hades", "Hollow Knight", "Celeste",
    "Sekiro", "Dark Souls III", "Bloodborne", "Red Dead Redemption 2",
    "God of War", "Horizon Zero Dawn", "Death Stranding", "Control",
    "Resident Evil Village", "It Takes Two", "Halo Infinite",
    "Forza Horizon 5", "Microsoft Flight Simulator", "Age of Empires IV",
    "Civilization VI", "Total War: WARHAMMER III", "Cities: Skylines",
    "Euro Truck Simulator 2", "Farming Simulator 22", "Satisfactory",
    "Factorio", "Rimworld", "Oxygen Not Included", "Don't Starve Together",
    "Deep Rock Galactic", "Risk of Rain 2", "Payday 2", "Left 4 Dead 2",
    "Garry's Mod", "VRChat", "Phasmophobia", "The Forest",
    "Green Hell", "Subnautica", "No Man's Sky", "Elite Dangerous",
    "Star Citizen", "Eve Online", "Final Fantasy XIV", "Black Desert Online",
    "Guild Wars 2", "Elder Scrolls Online", "New World", "Albion Online",
    "RuneScape", "Old School RuneScape", "World of Tanks", "War Thunder",
    "World of Warships", "Crossout", "Enlisted", "Hunt: Showdown",
    "Escape from Tarkov", "DayZ", "SCUM", "Arma 3", "Squad",
    "Hell Let Loose", "Post Scriptum", "Insurgency: Sandstorm",
    "Ready or Not", "Zero Hour", "Ground Branch", "GTFO",
    "Back 4 Blood", "Warhammer: Vermintide 2", "Darktide",
    "Total War: Three Kingdoms", "Mount & Blade II: Bannerlord",
    "Crusader Kings III", "Europa Universalis IV", "Hearts of Iron IV",
    "Stellaris", "Victoria 3", "Imperator: Rome"
]

# 日志设定
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
            compression_type='gzip',  # 启用压缩提高性能
            batch_size=16384,
            linger_ms=10
        )
        logger.info("✓ Kafka Producer 连线成功")
        return producer
    except KafkaError as e:
        logger.error(f"✗ Kafka 连线失败: {e}")
        raise

# ================== 假数据生成 ==================
def generate_fake_game_data(num_games: int) -> List[Dict]:
    """
    生成假的游戏统计数据
    schema: game_id, game_name, current_players, peak_today, rank, fetch_time
    """
    fake_data = []
    fetch_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    # 使用前 num_games 个游戏名称，保持一致性
    selected_games = FAKE_GAME_NAMES[:num_games]

    for rank, game_name in enumerate(selected_games, 1):
        # 生成游戏 ID（基于名称哈希保持一致）
        game_id = 1000 + hash(game_name) % 900000

        # 模拟玩家数：排名越前，玩家越多
        base_players = max(1000000 - (rank * 8000), 1000)
        # 添加随机波动 (±20%)
        current_players = int(base_players * random.uniform(0.8, 1.2))

        # 今日峰值略高于当前玩家数
        peak_today = int(current_players * random.uniform(1.0, 1.3))

        game_record = {
            'game_id': game_id,
            'game_name': game_name,
            'current_players': current_players,
            'peak_today': peak_today,
            'rank': rank,
            'fetch_time': fetch_time
        }

        fake_data.append(game_record)

    return fake_data

# ================== 发送到 Kafka ==================
def send_batch_to_kafka(producer: KafkaProducer, data: List[Dict]) -> int:
    """批量发送数据到 Kafka"""
    success_count = 0

    for record in data:
        try:
            producer.send(KAFKA_TOPIC, value=record)
            success_count += 1
        except Exception as e:
            logger.error(f"发送失败: {e}")

    # 等待所有消息发送完成
    producer.flush()

    return success_count

# ================== 主程式 ==================
def main():
    """主执行流程"""
    logger.info("=== 假数据生成器启动 ===")
    logger.info(f"配置: 每 {SEND_INTERVAL} 秒发送 {BATCH_SIZE} 条数据")
    logger.info(f"预估吞吐量: {BATCH_SIZE / SEND_INTERVAL} 条/秒")
    logger.info("=" * 60)

    # 建立 Kafka Producer
    producer = create_kafka_producer()

    try:
        total_sent = 0
        iteration = 0

        while True:
            iteration += 1
            start_time = time.time()

            # 1. 生成假数据
            fake_data = generate_fake_game_data(BATCH_SIZE)

            # 2. 发送到 Kafka
            success_count = send_batch_to_kafka(producer, fake_data)
            total_sent += success_count

            elapsed = time.time() - start_time

            # 3. 显示统计
            if iteration % 10 == 0:  # 每 10 批显示一次
                logger.info(
                    f"批次 #{iteration} | "
                    f"本批: {success_count} 条 | "
                    f"累计: {total_sent} 条 | "
                    f"耗时: {elapsed:.2f}s | "
                    f"速率: {success_count/elapsed:.1f} 条/秒"
                )

            # 4. 等待下次发送
            sleep_time = max(0, SEND_INTERVAL - elapsed)
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        logger.info("\n收到中断信号，正在关闭...")
    except Exception as e:
        logger.error(f"程式错误: {e}")
    finally:
        producer.close()
        logger.info(f"已发送总计 {total_sent} 条数据")
        logger.info("=== 假数据生成器已停止 ===")

if __name__ == "__main__":
    main()
