-- ============================================================================
-- BQ2: Reliability Scores for All Major Routes with Time/Season Filtering
-- ============================================================================
-- Combines real-time flight data with historical Gold layer data
-- Output: Reliability scores for all major routes with filtering by time/season

WITH realtime_reliability AS (
    -- Real-time reliability metrics from mock API
    SELECT
        carrier_code,
        carrier_name,
        origin_airport,
        destination_airport,
        flight_date,
        hour_of_day,
        day_of_week,
        is_weekend,
        carrier_reliability_score,
        reliability_band,
        on_time,
        is_delayed,
        is_cancelled,
        arrival_delay_minutes,
        status,
        timestamp AS realtime_timestamp
    FROM
        realtime_flights
    WHERE
        timestamp >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
),

realtime_route_reliability AS (
    -- Aggregate real-time reliability by route
    SELECT
        carrier_code,
        carrier_name,
        origin_airport,
        destination_airport,
        hour_of_day,
        day_of_week,
        is_weekend,
        -- Derive season from flight_date
        CASE
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (12, 1, 2) THEN 'winter'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (3, 4, 5) THEN 'spring'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (6, 7, 8) THEN 'summer'
            ELSE 'fall'
        END AS season,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN on_time THEN 1 ELSE 0 END) AS on_time_flights,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS cancelled_flights,
        ROUND(100.0 * SUM(CASE WHEN on_time THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(carrier_reliability_score), 3) AS avg_reliability_score,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.5), 2) AS median_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.8), 2) AS p80_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.95), 2) AS p95_arrival_delay,
        MAX(reliability_band) AS current_reliability_band
    FROM
        realtime_reliability
    GROUP BY
        carrier_code, carrier_name, origin_airport, destination_airport,
        hour_of_day, day_of_week, is_weekend,
        CASE
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (12, 1, 2) THEN 'winter'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (3, 4, 5) THEN 'spring'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (6, 7, 8) THEN 'summer'
            ELSE 'fall'
        END
    HAVING
        COUNT(*) >= 10  -- Minimum sample size
),

historical_reliability AS (
    -- Historical reliability metrics from Gold layer
    SELECT
        UniqueCarrier AS carrier_code,
        Origin AS origin_airport,
        Dest AS destination_airport,
        flight_hour,
        season,
        COUNT(*) AS total_flights,
        SUM(on_time_flag) AS on_time_flights,
        SUM(cancelled_flag) AS cancelled_flights,
        ROUND(100.0 * SUM(on_time_flag) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(cancelled_flag) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(reliability_score), 3) AS avg_reliability_score,
        ROUND(AVG(ArrDelay), 2) AS avg_arrival_delay,
        ROUND(PERCENTILE_APPROX(ArrDelay, 0.5, 100), 2) AS median_arrival_delay,
        ROUND(PERCENTILE_APPROX(ArrDelay, 0.8, 100), 2) AS p80_arrival_delay,
        ROUND(PERCENTILE_APPROX(ArrDelay, 0.95, 100), 2) AS p95_arrival_delay
    FROM
        flight_features
    WHERE
        Year >= 2005
    GROUP BY
        UniqueCarrier, Origin, Dest, flight_hour, season
    HAVING
        COUNT(*) >= 30
)

-- Main Result: Reliability Scores with Real-Time + Historical
SELECT
    COALESCE(r.carrier_code, h.carrier_code) AS carrier_code,
    r.carrier_name,
    COALESCE(r.origin_airport, h.origin_airport) AS origin_airport,
    COALESCE(r.destination_airport, h.destination_airport) AS destination_airport,
    COALESCE(r.season, h.season) AS season,
    COALESCE(r.hour_of_day, h.flight_hour) AS hour_of_day,
    r.day_of_week,
    r.is_weekend,
    -- Real-time metrics
    r.total_flights AS realtime_flight_count,
    r.on_time_rate_pct AS realtime_on_time_rate_pct,
    r.cancellation_rate_pct AS realtime_cancellation_rate_pct,
    r.avg_reliability_score AS realtime_reliability_score,
    r.current_reliability_band,
    r.avg_arrival_delay AS realtime_avg_delay,
    r.median_arrival_delay AS realtime_median_delay,
    r.p80_arrival_delay AS realtime_p80_delay,
    r.p95_arrival_delay AS realtime_p95_delay,
    -- Historical metrics
    h.total_flights AS historical_flight_count,
    h.on_time_rate_pct AS historical_on_time_rate_pct,
    h.cancellation_rate_pct AS historical_cancellation_rate_pct,
    h.avg_reliability_score AS historical_reliability_score,
    h.avg_arrival_delay AS historical_avg_delay,
    h.median_arrival_delay AS historical_median_delay,
    h.p80_arrival_delay AS historical_p80_delay,
    h.p95_arrival_delay AS historical_p95_delay,
    -- Combined reliability score (weighted: 70% historical, 30% real-time)
    ROUND(
        COALESCE(h.avg_reliability_score, 0.5) * 0.7 +
        COALESCE(r.avg_reliability_score, 0.5) * 0.3,
    3) AS combined_reliability_score,
    -- Reliability band
    CASE
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 90 THEN 'EXCELLENT'
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 85 THEN 'HIGH'
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 70 THEN 'MEDIUM'
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 60 THEN 'LOW'
        ELSE 'POOR'
    END AS reliability_band,
    -- Star rating (1-5)
    CASE
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 90 THEN 5
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 80 THEN 4
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 70 THEN 3
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 60 THEN 2
        ELSE 1
    END AS reliability_stars,
    -- Trend indicator
    CASE
        WHEN r.on_time_rate_pct IS NOT NULL AND h.on_time_rate_pct IS NOT NULL THEN
            CASE
                WHEN r.on_time_rate_pct > h.on_time_rate_pct + 5 THEN 'IMPROVING'
                WHEN r.on_time_rate_pct < h.on_time_rate_pct - 5 THEN 'DECLINING'
                ELSE 'STABLE'
            END
        ELSE 'INSUFFICIENT_DATA'
    END AS trend
FROM
    realtime_route_reliability r
FULL OUTER JOIN
    historical_reliability h
    ON r.carrier_code = h.carrier_code
    AND r.origin_airport = h.origin_airport
    AND r.destination_airport = h.destination_airport
    AND r.hour_of_day = h.flight_hour
    AND r.season = h.season
WHERE
    COALESCE(r.total_flights, h.total_flights) >= 20  -- Minimum sample size
ORDER BY
    combined_reliability_score DESC,
    COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) DESC
LIMIT 2000;

