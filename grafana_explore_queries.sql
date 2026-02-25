-- ================================================================
-- Grafana Explore 快速查詢（Steam Kafka ClickHouse 專案）
-- 說明：
-- 1) 全部查詢都使用 MergeTree 實體表（steam_top_games / steam_game_details）
-- 2) 不要直接查 kafka_* 表，避免 QUERY_NOT_ALLOWED / Code 620
-- ================================================================

-- 1) 資料是否有在更新（freshness）
SELECT
    max(fetch_time) AS latest_fetch_time,
    dateDiff('minute', max(fetch_time), now()) AS lag_minutes
FROM steam_top_games;

-- 2) 最新排行榜前 20
SELECT
    rank,
    game_name,
    current_players,
    peak_today,
    fetch_time
FROM steam_top_games
WHERE fetch_time = (SELECT max(fetch_time) FROM steam_top_games)
ORDER BY rank
LIMIT 20;

-- 3) 最近 24h 單一遊戲玩家趨勢（把 730 換成你要的 game_id）
SELECT
    toStartOfInterval(fetch_time, INTERVAL 10 minute) AS time,
    avg(current_players) AS players
FROM steam_top_games
WHERE fetch_time >= now() - INTERVAL 24 HOUR
  AND game_id = 730
GROUP BY time
ORDER BY time;

-- 4) 最近 24h 總玩家數趨勢
SELECT
    toStartOfInterval(fetch_time, INTERVAL 10 minute) AS time,
    sum(current_players) AS total_players
FROM steam_top_games
WHERE fetch_time >= now() - INTERVAL 24 HOUR
GROUP BY time
ORDER BY time;

-- 5) 熱門 + 有折扣遊戲（Top 20）
SELECT
    g.rank,
    g.game_name,
    g.current_players,
    d.original_price,
    d.discount_percent,
    d.final_price,
    d.review_score
FROM steam_top_games g
INNER JOIN (
    SELECT
        game_id,
        argMax(original_price, fetch_time) AS original_price,
        argMax(discount_percent, fetch_time) AS discount_percent,
        argMax(final_price, fetch_time) AS final_price,
        argMax(review_score, fetch_time) AS review_score
    FROM steam_game_details
    GROUP BY game_id
) d ON g.game_id = d.game_id
WHERE g.fetch_time = (SELECT max(fetch_time) FROM steam_top_games)
  AND d.discount_percent > 0
ORDER BY g.current_players DESC
LIMIT 20;

-- 6) 類型佔比（以當前玩家數加總）
SELECT
    genre,
    sum(current_players) AS players
FROM (
    SELECT
        g.current_players,
        arrayJoin(d.genres) AS genre
    FROM steam_top_games g
    INNER JOIN (
        SELECT
            game_id,
            argMax(genres, fetch_time) AS genres
        FROM steam_game_details
        GROUP BY game_id
    ) d ON g.game_id = d.game_id
    WHERE g.fetch_time = (SELECT max(fetch_time) FROM steam_top_games)
)
WHERE genre != ''
GROUP BY genre
ORDER BY players DESC
LIMIT 12;

