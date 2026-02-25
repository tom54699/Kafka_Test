# 脚本使用指南

本项目包含多个 Shell 脚本，用于简化 Kafka + ClickHouse 数据管线的部署和管理。

## 📋 脚本总览

| 脚本名称 | 用途 | 使用场景 |
|---------|------|---------|
| `setup.sh` | 一次性初始化设置 | 首次部署项目 |
| `start_producers.sh` | 启动真实数据 Producers | 使用 Steam API 获取真实数据 |
| `start_fake_producers.sh` | 启动假数据生成器 | 压力测试、开发调试 |
| `stop_producers.sh` | 停止所有 Producers | 停止数据生成 |
| `recreate_kafka_tables.sh` | 重建 Kafka Engine 表 | 更新配置或重置消费者 |

---

## 🚀 脚本详细说明

### 1. setup.sh - 初始化设置脚本

**用途**: 一次性完成项目的所有初始化工作

**执行内容**:
- ✅ 检查 Docker 和 Docker Compose 是否安装
- ✅ 启动基础设施（Kafka, ClickHouse, Grafana）
- ✅ 创建 Kafka Topics
- ✅ 执行 ClickHouse Schema（创建表和 Materialized Views）
- ✅ 安装 Python 依赖包
- ✅ 创建日志目录
- ✅ 设置脚本执行权限

**使用方法**:
```bash
./setup.sh
```

**预期时间**: 约 30-60 秒

**注意事项**:
- 只需在首次部署时执行一次
- 如果 Docker 服务未启动，会报错并终止
- 如果已有同名的 Topics 或表，会跳过创建

---

### 2. start_producers.sh - 启动真实数据 Producers

**用途**: 启动两个 Python Producers，从 Steam API 获取真实游戏数据

**启动的服务**:
1. `steam_top_games_producer.py` - 每 10 分钟抓取热门游戏统计
2. `steam_game_details_producer.py` - 每 1 小时抓取游戏详细信息

**数据流向**:
```
Steam API → Producers → Kafka Topics → ClickHouse
```

**使用方法**:
```bash
./start_producers.sh
```

**数据量**:
- 热门游戏: ~100 条/10分钟 = 10 条/分钟
- 游戏详情: ~100 条/小时 = 1.67 条/分钟

**日志查看**:
```bash
tail -f logs/top_games.log
tail -f logs/game_details.log
```

**停止方法**:
```bash
./stop_producers.sh
```

---

### 3. start_fake_producers.sh - 启动假数据生成器

**用途**: 启动高频假数据生成器，用于压力测试和性能调优

**启动的服务**:
1. `fake_steam_top_games_producer.py` - 高频生成热门游戏数据
2. `fake_steam_game_details_producer.py` - 高频生成游戏详情数据

**数据流向**:
```
假数据生成器 → Kafka Topics → ClickHouse
（使用与真实数据相同的 Topics 和 Schema）
```

**使用方法**:
```bash
./start_fake_producers.sh
```

**当前配置的吞吐量**:
- steam_top_games: 20,000 条/秒
- steam_game_details: 10,000 条/秒
- **总计: 30,000 条/秒**

**性能对比**:

| 模式 | 吞吐量 | 适用场景 |
|-----|--------|---------|
| 真实数据 | ~12 条/分钟 | 生产环境、真实数据分析 |
| 假数据 | 30,000 条/秒 | 压力测试、性能调优 |

**调整吞吐量**:
编辑 `fake_steam_top_games_producer.py` 和 `fake_steam_game_details_producer.py`:
```python
SEND_INTERVAL = 0.05  # 发送间隔（秒）
BATCH_SIZE = 1000     # 每批数量
```

**数据增长预估**（当前配置）:
- 每分钟: 1,800,000 条
- 每小时: 108,000,000 条（1.08 亿）
- 每天: 2,592,000,000 条（25.92 亿）

**日志查看**:
```bash
tail -f logs/fake_top_games.log
tail -f logs/fake_game_details.log
```

**实时监控数据增长**:
```bash
watch -n 1 'docker exec clickhouse-server clickhouse-client --query "SELECT count() FROM steam_top_games"'
```

**停止方法**:
```bash
./stop_producers.sh
```

---

### 4. stop_producers.sh - 停止所有 Producers

**用途**: 停止所有正在运行的 Producers（真实 + 假数据）

**执行内容**:
- 查找所有 producer 进程
- 优雅停止（SIGTERM）
- 如果无法停止，强制终止（SIGKILL）
- 验证所有进程已停止

**使用方法**:
```bash
./stop_producers.sh
```

**停止的进程**:
- steam_top_games_producer.py
- steam_game_details_producer.py
- fake_steam_top_games_producer.py
- fake_steam_game_details_producer.py

---

### 5. recreate_kafka_tables.sh - 重建 Kafka Engine 表

**用途**: 删除并重新创建 ClickHouse 的 Kafka Engine 表和 Materialized Views

**使用场景**:
- 更新 Kafka 消费者配置（如增加 consumer 数量）
- 重置消费者 offset
- 修复损坏的 Kafka Engine 表

**执行内容**:
1. 删除 Materialized Views
2. 删除 Kafka Engine 表
3. 重新创建 Kafka Engine 表（使用优化配置）
4. 重新创建 Materialized Views

**优化配置**:
```
kafka_num_consumers: 3           # 并行消费者数量
kafka_flush_interval_ms: 1000    # 刷新间隔 1 秒
kafka_poll_timeout_ms: 1000      # 轮询超时 1 秒
kafka_max_block_size: 100        # 批量大小
```

**使用方法**:
```bash
./recreate_kafka_tables.sh
```

**注意事项**:
- ⚠️ **不会**删除 MergeTree 表（实际数据不会丢失）
- ⚠️ **会**创建新的 Consumer Group（_v2）
- ⚠️ 新 Consumer Group 从最新 offset 开始消费

---

## 🔄 常见工作流

### 场景 1: 首次部署项目

```bash
# 1. 初始化项目
./setup.sh

# 2. 启动真实数据采集
./start_producers.sh

# 3. 查看日志确认运行正常
tail -f logs/top_games.log

# 4. 访问 Grafana 查看数据
# http://localhost:3000
```

### 场景 2: 压力测试

```bash
# 1. 停止真实数据（如果正在运行）
./stop_producers.sh

# 2. 启动假数据生成器
./start_fake_producers.sh

# 3. 实时监控数据增长
watch -n 1 'docker exec clickhouse-server clickhouse-client --query "SELECT count() FROM steam_top_games"'

# 4. 监控资源使用
watch -n 1 'docker stats --no-stream kafka clickhouse-server'

# 5. 测试完成后停止
./stop_producers.sh
```

### 场景 3: 更新 Kafka 消费配置

```bash
# 1. 停止所有 Producers
./stop_producers.sh

# 2. 重建 Kafka Engine 表（应用新配置）
./recreate_kafka_tables.sh

# 3. 重新启动 Producers
./start_fake_producers.sh  # 或 ./start_producers.sh
```

### 场景 4: 清理并重新开始

```bash
# 1. 停止 Producers
./stop_producers.sh

# 2. 停止基础设施
docker-compose down -v

# 3. 重新初始化
./setup.sh

# 4. 启动数据采集
./start_producers.sh
```

---

## 📊 性能监控命令

### 查看 ClickHouse 数据量
```bash
docker exec clickhouse-server clickhouse-client --query "
SELECT
    table,
    formatReadableQuantity(sum(rows)) as rows,
    formatReadableSize(sum(bytes)) as size
FROM system.parts
WHERE active AND database = 'default'
GROUP BY table
"
```

### 查看 Kafka Consumer Lag
```bash
docker exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe \
  --group clickhouse_steam_top_games_consumer_v2
```

### 查看 Docker 容器资源使用
```bash
docker stats --no-stream kafka clickhouse-server grafana
```

### 查看正在运行的 Producers
```bash
ps aux | grep producer.py | grep -v grep
```

---

## ⚙️ 脚本配置参数

### 假数据生成器参数

在 `fake_steam_top_games_producer.py` 中:
```python
SEND_INTERVAL = 0.05  # 每 0.05 秒发送一批
BATCH_SIZE = 1000     # 每批 1000 条
```

在 `fake_steam_game_details_producer.py` 中:
```python
SEND_INTERVAL = 0.1   # 每 0.1 秒发送一批
BATCH_SIZE = 1000     # 每批 1000 条
```

**吞吐量方案**:

| 方案 | INTERVAL | BATCH_SIZE | 吞吐量 |
|-----|----------|------------|--------|
| 轻量 | 1 秒 | 50 | 50 条/秒 |
| 中等 | 0.2 秒 | 200 | 1,000 条/秒 |
| 高压 | 0.1 秒 | 500 | 5,000 条/秒 |
| 极限 | 0.05 秒 | 1000 | 20,000 条/秒 |

---

## 🐛 故障排查

### Producer 无法启动
```bash
# 检查 Kafka 是否运行
docker ps | grep kafka

# 检查 Kafka 连接
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092

# 查看 Producer 日志
tail -100 logs/top_games.log
```

### ClickHouse 不消费数据
```bash
# 检查 Kafka Engine 表
docker exec clickhouse-server clickhouse-client --query "SELECT * FROM kafka_steam_top_games LIMIT 1"

# 检查消费者状态
docker exec clickhouse-server clickhouse-client --query "SELECT * FROM system.kafka_consumers FORMAT Vertical"

# 重建 Kafka 表
./recreate_kafka_tables.sh
```

### 脚本权限问题
```bash
# 添加执行权限
chmod +x *.sh
```

---

## 📝 最佳实践

1. **首次部署**: 先运行 `setup.sh`，确保所有基础设施就绪
2. **开发调试**: 使用假数据生成器，调整吞吐量到合适的值
3. **生产环境**: 使用真实数据 Producers，监控 Steam API rate limit
4. **性能测试**: 逐步提升假数据吞吐量，观察系统瓶颈
5. **定期清理**: 根据 TTL 设置，定期清理历史数据

---

## 🔗 相关文档

- [README.md](README.md) - 项目总览
- [QUICK_START.md](QUICK_START.md) - 快速入门
- [HIGH_FREQUENCY_CONFIG.md](HIGH_FREQUENCY_CONFIG.md) - 高频配置说明
- [KAFKA_UI_GUIDE.md](KAFKA_UI_GUIDE.md) - Kafka UI 使用指南
