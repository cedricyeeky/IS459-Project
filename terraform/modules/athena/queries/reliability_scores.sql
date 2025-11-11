-- ============================================================================
-- BQ2: Reliability Scores for All Major Routes with Time/Season Filtering
-- ============================================================================
-- Combines real-time flight data with historical Gold layer data
-- Output: Reliability scores for all major routes with filtering by time/season

WITH realtime_route_reliability AS (
    -- Real-time reliability metrics from mock API
    SELECT
        carrier,
        origin_airport,
        destination_airport,
        hour_of_day,
        day_of_week,
        -- Derive season from flight_date
        CASE
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (12, 1, 2) THEN 'winter'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (3, 4, 5) THEN 'spring'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (6, 7, 8) THEN 'summer'
            ELSE 'fall'
        END AS season,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN arrival_delay_minutes <= 15 THEN 1 ELSE 0 END) AS on_time_flights,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS cancelled_flights,
        ROUND(100.0 * SUM(CASE WHEN arrival_delay_minutes <= 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.5), 2) AS median_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.8), 2) AS p80_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.95), 2) AS p95_arrival_delay
    FROM
        "flight-delays-dev-db".flights
    WHERE
        FROM_ISO8601_TIMESTAMP(timestamp) >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
    GROUP BY
        carrier, origin_airport, destination_airport,
        hour_of_day, day_of_week,
        CASE
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (12, 1, 2) THEN 'winter'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (3, 4, 5) THEN 'spring'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (6, 7, 8) THEN 'summer'
            ELSE 'fall'
        END
    HAVING
        COUNT(*) >= 5
),

historical_reliability AS (
    -- Historical reliability metrics from Gold layer
    SELECT
        UniqueCarrier AS carrier,
        Origin AS origin_airport,
        Dest AS destination_airport,
        flight_hour AS hour_of_day,
        season,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) <= 15 THEN 1 ELSE 0 END) AS on_time_flights,
        SUM(cancelled) AS cancelled_flights,
        ROUND(100.0 * SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) <= 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(cancelled) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(TRY_CAST(arrdelay AS DOUBLE)), 2) AS avg_arrival_delay,
        ROUND(APPROX_PERCENTILE(TRY_CAST(arrdelay AS DOUBLE), 0.5), 2) AS median_arrival_delay,
        ROUND(APPROX_PERCENTILE(TRY_CAST(arrdelay AS DOUBLE), 0.8), 2) AS p80_arrival_delay,
        ROUND(APPROX_PERCENTILE(TRY_CAST(arrdelay AS DOUBLE), 0.95), 2) AS p95_arrival_delay
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 1987
        AND flight_hour IS NOT NULL
    GROUP BY
        UniqueCarrier, Origin, Dest, flight_hour, season
    HAVING
        COUNT(*) >= 10
)

-- Main Result: Combined Reliability Scores
SELECT
    COALESCE(r.carrier, h.carrier) AS carrier,
    COALESCE(r.origin_airport, h.origin_airport) AS origin_airport,
    COALESCE(r.destination_airport, h.destination_airport) AS destination_airport,
    COALESCE(r.hour_of_day, h.hour_of_day) AS hour_of_day,
    COALESCE(r.season, h.season) AS season,
    r.day_of_week,
    -- Real-time metrics
    r.total_flights AS realtime_flight_count,
    r.on_time_rate_pct AS realtime_on_time_rate_pct,
    r.cancellation_rate_pct AS realtime_cancellation_rate_pct,
    r.avg_arrival_delay AS realtime_avg_delay,
    r.median_arrival_delay AS realtime_median_delay,
    r.p80_arrival_delay AS realtime_p80_delay,
    r.p95_arrival_delay AS realtime_p95_delay,
    -- Historical metrics
    h.total_flights AS historical_flight_count,
    h.on_time_rate_pct AS historical_on_time_rate_pct,
    h.cancellation_rate_pct AS historical_cancellation_rate_pct,
    h.avg_arrival_delay AS historical_avg_delay,
    h.median_arrival_delay AS historical_median_delay,
    h.p80_arrival_delay AS historical_p80_delay,
    h.p95_arrival_delay AS historical_p95_delay,
    -- Combined reliability score (weighted average: 60% historical, 40% real-time)
    ROUND(
        COALESCE(h.on_time_rate_pct, 0.0) * 0.6 +
        COALESCE(r.on_time_rate_pct, 0.0) * 0.4,
    2) AS combined_reliability_score,
    -- Reliability band based on combined score
    CASE
        WHEN COALESCE(h.on_time_rate_pct, 0.0) * 0.6 + COALESCE(r.on_time_rate_pct, 0.0) * 0.4 >= 90 THEN 'EXCELLENT'
        WHEN COALESCE(h.on_time_rate_pct, 0.0) * 0.6 + COALESCE(r.on_time_rate_pct, 0.0) * 0.4 >= 80 THEN 'GOOD'
        WHEN COALESCE(h.on_time_rate_pct, 0.0) * 0.6 + COALESCE(r.on_time_rate_pct, 0.0) * 0.4 >= 70 THEN 'FAIR'
        ELSE 'POOR'
    END AS reliability_band
FROM
    realtime_route_reliability r
FULL OUTER JOIN
    historical_reliability h
    ON r.carrier = h.carrier
    AND r.origin_airport = h.origin_airport
    AND r.destination_airport = h.destination_airport
    AND r.hour_of_day = h.hour_of_day
    AND r.season = h.season
ORDER BY
    combined_reliability_score DESC,
    carrier, origin_airport, destination_airport;
