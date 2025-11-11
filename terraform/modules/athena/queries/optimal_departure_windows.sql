-- OPTIMAL DEPARTURE WINDOWS
-- Rewritten to use actual available schema from flights table
-- Original purpose: Identify best departure hours with lowest delays
-- Simplified: Derives on_time from arrival_delay_minutes threshold

WITH flight_performance AS (
    SELECT
        origin_airport,
        destination_airport,
        carrier,
        hour_of_day,
        day_of_week,
        flight_date,
        arrival_delay_minutes,
        departure_delay_minutes,
        is_cancelled,
        CASE WHEN arrival_delay_minutes <= 15 THEN 1 ELSE 0 END AS on_time_flag,
        CASE WHEN arrival_delay_minutes > 15 THEN 1 ELSE 0 END AS delayed_flag,
        CASE WHEN is_cancelled = true THEN 1 ELSE 0 END AS cancelled_flag
    FROM "flight-delays-dev-db".flights
    WHERE FROM_ISO8601_TIMESTAMP(timestamp) >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
),

hourly_performance AS (
    SELECT
        origin_airport,
        destination_airport,
        hour_of_day,
        day_of_week,
        COUNT(*) AS total_flights,
        SUM(on_time_flag) AS on_time_count,
        SUM(delayed_flag) AS delayed_count,
        SUM(cancelled_flag) AS cancelled_count,
        ROUND(100.0 * SUM(on_time_flag) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(delayed_flag) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(100.0 * SUM(cancelled_flag) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(AVG(departure_delay_minutes), 2) AS avg_departure_delay,
        ROUND(STDDEV(arrival_delay_minutes), 2) AS stddev_arrival_delay
    FROM flight_performance
    GROUP BY origin_airport, destination_airport, hour_of_day, day_of_week
    HAVING COUNT(*) >= 2  -- Require minimum sample size
),

carrier_hourly_performance AS (
    SELECT
        carrier,
        hour_of_day,
        day_of_week,
        COUNT(*) AS total_flights,
        ROUND(100.0 * SUM(on_time_flag) / NULLIF(COUNT(*), 0), 2) AS carrier_on_time_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS carrier_avg_delay
    FROM flight_performance
    GROUP BY carrier, hour_of_day, day_of_week
    HAVING COUNT(*) >= 2
),

departure_windows_ranked AS (
    SELECT
        hp.origin_airport,
        hp.destination_airport,
        hp.hour_of_day,
        hp.day_of_week,
        hp.total_flights,
        hp.on_time_rate_pct,
        hp.delay_rate_pct,
        hp.cancellation_rate_pct,
        hp.avg_arrival_delay,
        hp.avg_departure_delay,
        hp.stddev_arrival_delay,
        chp.carrier_on_time_rate_pct AS carrier_avg_on_time_rate,
        -- Optimal window score: higher on_time rate + lower std dev = better
        ROUND(hp.on_time_rate_pct - (COALESCE(hp.stddev_arrival_delay, 0) / 2), 2) AS window_quality_score,
        ROW_NUMBER() OVER (
            PARTITION BY hp.origin_airport, hp.destination_airport, hp.day_of_week
            ORDER BY hp.on_time_rate_pct DESC, hp.avg_arrival_delay ASC
        ) AS hour_rank
    FROM hourly_performance hp
    LEFT JOIN carrier_hourly_performance chp 
        ON hp.hour_of_day = chp.hour_of_day 
        AND hp.day_of_week = chp.day_of_week
)

-- FINAL OUTPUT: Optimal departure windows by route and day
SELECT
    origin_airport,
    destination_airport,
    day_of_week,
    hour_of_day AS optimal_departure_hour,
    hour_rank,
    total_flights,
    on_time_rate_pct,
    delay_rate_pct,
    cancellation_rate_pct,
    avg_arrival_delay,
    avg_departure_delay,
    stddev_arrival_delay,
    carrier_avg_on_time_rate,
    window_quality_score,
    CASE
        WHEN hour_of_day BETWEEN 5 AND 8 THEN 'EARLY_MORNING'
        WHEN hour_of_day BETWEEN 9 AND 11 THEN 'LATE_MORNING'
        WHEN hour_of_day BETWEEN 12 AND 16 THEN 'AFTERNOON'
        WHEN hour_of_day BETWEEN 17 AND 20 THEN 'EVENING'
        ELSE 'NIGHT'
    END AS time_window,
    CASE
        WHEN on_time_rate_pct >= 85 THEN 'EXCELLENT'
        WHEN on_time_rate_pct >= 70 THEN 'GOOD'
        WHEN on_time_rate_pct >= 50 THEN 'FAIR'
        ELSE 'POOR'
    END AS window_quality
FROM departure_windows_ranked
WHERE hour_rank <= 3  -- Top 3 hours per route per day
ORDER BY origin_airport, destination_airport, day_of_week, hour_rank
LIMIT 100;
