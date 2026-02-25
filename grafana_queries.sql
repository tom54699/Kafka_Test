-- ================================================================
-- Grafana Dashboard SQL 查詢範例
-- ================================================================
-- 專案：Steam 數據管線視覺化
-- 說明：以下 SQL 查詢可直接在 Grafana 的 ClickHouse Data Source 中使用
-- 使用方式：在 Grafana 建立 Dashboard -> 新增 Panel -> 選擇 ClickHouse -> 貼上查詢
-- ================================================================

-- ================================================================
-- 1. 即時熱門遊戲排行榜 (Top 20)
-- ================================================================
-- 用途：顯示當前最熱門的 20 款遊戲及其即時玩家數
-- 視覺化建議：Table 或 Bar Chart

SELECT
    rank,
    game_name,
    current_players,
    peak_today,
    fetch_time
FROM steam_top_games
WHERE fetch_time = (SELECT max(fetch_time) FROM steam_top_games)
ORDER BY rank ASC
LIMIT 20;

-- ================================================================
-- 2. 遊戲玩家數時間序列（過去 24 小時）
-- ================================================================
-- 用途：追蹤特定遊戲的玩家數變化趨勢
-- 視覺化建議：Time Series Graph
-- 說明：將 game_id 替換為想要追蹤的遊戲 ID
--       例如：730 = CS2, 570 = Dota 2, 1938090 = Call of Duty

SELECT
    $__timeInterval(fetch_time) as time,
    game_name,
    avg(current_players) as avg_players,
    max(current_players) as max_players,
    min(current_players) as min_players
FROM steam_top_games
WHERE
    game_id IN (730, 570, 1938090)  -- 可替換為其他遊戲 ID
    AND $__timeFilter(fetch_time)
GROUP BY time, game_name
ORDER BY time ASC;

-- ================================================================
-- 3. 多遊戲玩家數對比（時間序列）
-- ================================================================
-- 用途：比較多款遊戲的玩家數變化
-- 視覺化建議：Time Series Graph (多線條)
-- Grafana 變數設定：建立變數 $game_ids (Multi-value, 從 steam_top_games 的 game_id 選擇)

SELECT
    $__timeInterval(fetch_time) as time,
    game_name,
    avg(current_players) as players
FROM steam_top_games
WHERE
    $__timeFilter(fetch_time)
    -- 使用 Grafana 變數：AND game_id IN ($game_ids)
GROUP BY time, game_name
ORDER BY time ASC;

-- ================================================================
-- 4. 熱門遊戲折扣排行
-- ================================================================
-- 用途：找出目前最熱門且有折扣的遊戲
-- 視覺化建議：Table

SELECT
    g.rank,
    g.game_name,
    g.current_players,
    d.original_price,
    d.discount_percent,
    d.final_price,
    d.review_score,
    d.total_reviews
FROM steam_top_games g
INNER JOIN (
    SELECT
        game_id,
        argMax(original_price, fetch_time) as original_price,
        argMax(discount_percent, fetch_time) as discount_percent,
        argMax(final_price, fetch_time) as final_price,
        argMax(review_score, fetch_time) as review_score,
        argMax(total_reviews, fetch_time) as total_reviews
    FROM steam_game_details
    WHERE fetch_time >= now() - INTERVAL 1 DAY
    GROUP BY game_id
) d ON g.game_id = d.game_id
WHERE
    g.fetch_time >= now() - INTERVAL 1 HOUR
    AND d.discount_percent > 0
ORDER BY g.current_players DESC
LIMIT 20;

-- ================================================================
-- 5. 遊戲類型玩家數分布
-- ================================================================
-- 用途：統計不同遊戲類型的總玩家數
-- 視覺化建議：Pie Chart 或 Bar Chart

SELECT
    arrayJoin(genres) as genre,
    sum(current_players) as total_players,
    count() as game_count
FROM steam_top_games g
INNER JOIN (
    SELECT
        game_id,
        argMax(genres, fetch_time) as genres
    FROM steam_game_details
    GROUP BY game_id
) d ON g.game_id = d.game_id
WHERE g.fetch_time = (SELECT max(fetch_time) FROM steam_top_games)
GROUP BY genre
ORDER BY total_players DESC
LIMIT 15;

-- ================================================================
-- 6. 評價分數 vs 玩家數散點圖
-- ================================================================
-- 用途：分析遊戲評價與玩家數的關聯
-- 視覺化建議：Scatter Plot (需要 Grafana 插件)

SELECT
    g.game_name,
    g.current_players,
    d.review_score,
    d.total_reviews
FROM steam_top_games g
INNER JOIN (
    SELECT
        game_id,
        argMax(review_score, fetch_time) as review_score,
        argMax(total_reviews, fetch_time) as total_reviews
    FROM steam_game_details
    GROUP BY game_id
) d ON g.game_id = d.game_id
WHERE
    g.fetch_time >= now() - INTERVAL 1 HOUR
    AND d.total_reviews > 1000  -- 過濾評價數太少的遊戲
ORDER BY g.current_players DESC
LIMIT 100;

-- ================================================================
-- 7. 玩家數成長率排行（過去 6 小時）
-- ================================================================
-- 用途：找出玩家數成長最快的遊戲
-- 視覺化建議：Table

WITH
    latest AS (
        SELECT
            game_id,
            game_name,
            current_players as latest_players
        FROM steam_top_games
        WHERE fetch_time = (SELECT max(fetch_time) FROM steam_top_games)
    ),
    six_hours_ago AS (
        SELECT
            game_id,
            avg(current_players) as past_players
        FROM steam_top_games
        WHERE fetch_time >= now() - INTERVAL 6 HOUR
          AND fetch_time < now() - INTERVAL 5 HOUR
        GROUP BY game_id
    )
SELECT
    l.game_name,
    l.latest_players,
    s.past_players,
    round((l.latest_players - s.past_players) / s.past_players * 100, 2) as growth_percent
FROM latest l
INNER JOIN six_hours_ago s ON l.game_id = s.game_id
WHERE s.past_players > 0
ORDER BY growth_percent DESC
LIMIT 20;

-- ================================================================
-- 8. 每小時平均玩家數趨勢（過去 7 天）
-- ================================================================
-- 用途：觀察整體 Steam 平台的活躍度變化
-- 視覺化建議：Time Series Graph

SELECT
    toStartOfHour(fetch_time) as hour,
    sum(current_players) as total_players,
    count(DISTINCT game_id) as game_count,
    avg(current_players) as avg_players_per_game
FROM steam_top_games
WHERE fetch_time >= now() - INTERVAL 7 DAY
GROUP BY hour
ORDER BY hour ASC;

-- ================================================================
-- 9. 免費遊戲 vs 付費遊戲玩家數對比
-- ================================================================
-- 用途：比較免費遊戲與付費遊戲的熱門程度
-- 視覺化建議：Bar Chart

SELECT
    if(d.original_price = 0, 'Free', 'Paid') as game_type,
    count(DISTINCT g.game_id) as game_count,
    sum(g.current_players) as total_players,
    avg(g.current_players) as avg_players
FROM steam_top_games g
INNER JOIN (
    SELECT
        game_id,
        argMax(original_price, fetch_time) as original_price
    FROM steam_game_details
    GROUP BY game_id
) d ON g.game_id = d.game_id
WHERE g.fetch_time >= now() - INTERVAL 1 HOUR
GROUP BY game_type
ORDER BY total_players DESC;

-- ================================================================
-- 10. 開發商遊戲玩家數排行
-- ================================================================
-- 用途：統計哪些開發商的遊戲最受歡迎
-- 視覺化建議：Table 或 Bar Chart

SELECT
    arrayJoin(developers) as developer,
    count(DISTINCT g.game_id) as game_count,
    sum(g.current_players) as total_players,
    max(g.current_players) as max_players_single_game
FROM steam_top_games g
INNER JOIN (
    SELECT
        game_id,
        argMax(developers, fetch_time) as developers
    FROM steam_game_details
    GROUP BY game_id
) d ON g.game_id = d.game_id
WHERE
    g.fetch_time >= now() - INTERVAL 1 HOUR
    AND developer != ''
GROUP BY developer
ORDER BY total_players DESC
LIMIT 20;

-- ================================================================
-- 11. 單一遊戲詳細統計（Grafana 單一 Panel）
-- ================================================================
-- 用途：顯示特定遊戲的完整資訊
-- 視覺化建議：Stat Panel 或 Table
-- Grafana 變數：$game_id (選擇特定遊戲)

SELECT
    g.game_name,
    g.current_players,
    g.peak_today,
    g.rank,
    d.developers,
    d.publishers,
    d.genres,
    d.original_price,
    d.discount_percent,
    d.final_price,
    d.review_score,
    d.total_reviews,
    d.release_date
FROM steam_top_games g
INNER JOIN (
    SELECT
        game_id,
        argMax(developers, fetch_time) as developers,
        argMax(publishers, fetch_time) as publishers,
        argMax(genres, fetch_time) as genres,
        argMax(original_price, fetch_time) as original_price,
        argMax(discount_percent, fetch_time) as discount_percent,
        argMax(final_price, fetch_time) as final_price,
        argMax(review_score, fetch_time) as review_score,
        argMax(total_reviews, fetch_time) as total_reviews,
        argMax(release_date, fetch_time) as release_date
    FROM steam_game_details
    GROUP BY game_id
) d ON g.game_id = d.game_id
WHERE
    g.fetch_time = (SELECT max(fetch_time) FROM steam_top_games)
    -- 使用 Grafana 變數：AND g.game_id = $game_id
LIMIT 1;

-- ================================================================
-- 12. 總覽儀表板統計數字（Stat Panels）
-- ================================================================

-- 當前總玩家數
SELECT sum(current_players) as total_current_players
FROM steam_top_games
WHERE fetch_time = (SELECT max(fetch_time) FROM steam_top_games);

-- 追蹤遊戲總數
SELECT count(DISTINCT game_id) as total_games
FROM steam_top_games
WHERE fetch_time = (SELECT max(fetch_time) FROM steam_top_games);

-- 平均折扣百分比
SELECT avg(discount_percent) as avg_discount
FROM steam_game_details
WHERE
    fetch_time >= now() - INTERVAL 1 DAY
    AND discount_percent > 0;

-- 平均遊戲評價分數
SELECT avg(review_score) as avg_review_score
FROM steam_game_details
WHERE fetch_time >= now() - INTERVAL 1 DAY;

-- ================================================================
-- Grafana 設定建議
-- ================================================================
-- 1. Data Source 設定：
--    - Type: ClickHouse
--    - URL: http://localhost:8123
--    - Database: default
--
-- 2. 建議建立的變數 (Variables)：
--    - $game_ids: Multi-value, Query: SELECT DISTINCT game_id FROM steam_top_games LIMIT 100
--    - $game_id: Single value, Query: SELECT game_id FROM steam_top_games WHERE fetch_time = (SELECT max(fetch_time) FROM steam_top_games) ORDER BY rank LIMIT 50
--    - $time_range: Interval, 1h,6h,24h,7d,30d
--
-- 3. Dashboard 布局建議：
--    Row 1: 總覽統計（4 個 Stat Panels）
--    Row 2: 熱門遊戲排行榜（Table）
--    Row 3: 玩家數時間序列（Time Series Graph）
--    Row 4: 折扣遊戲 + 遊戲類型分布（Table + Pie Chart）
--    Row 5: 評價分析（Scatter Plot 或 Bar Chart）
-- ================================================================
