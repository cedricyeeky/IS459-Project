-- ============================================================================
-- BQ2: Optimal Departure Window Recommendations
-- ============================================================================
-- Combines real-time flight data with historical Gold layer data
-- Output: Optimal departure window recommendations

WITH realtime_hourly_performance AS (
    -- Real-time performance by hour from mock API
    SELECT
        origin_airport,
        destination_airport,
        hour_of_day,
        day_of_week,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN on_time THEN 1 ELSE 0 END) AS on_time_flights,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS cancelled_flights,
        ROUND(100.0 * SUM(CASE WHEN on_time THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(AVG(departure_delay_minutes), 2) AS avg_departure_delay
    FROM
        realtime_flights
    WHERE
        timestamp >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
        AND status IN ('scheduled', 'departed', 'arrived', 'landed')
    GROUP BY
        origin_airport, destination_airport, hour_of_day, day_of_week
    HAVING
        COUNT(*) >= 10
),

historical_hourly_performance AS (
    -- Historical performance by hour from Gold layer
    SELECT
        Origin AS origin_airport,
        Dest AS destination_airport,
        flight_hour,
        DayOfWeek,
        COUNT(*) AS total_flights,
        SUM(on_time_flag) AS on_time_flights,
        SUM(cancelled_flag) AS cancelled_flights,
        ROUND(100.0 * SUM(on_time_flag) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(cancelled_flag) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(ArrDelay), 2) AS avg_arrival_delay,
        ROUND(AVG(DepDelay), 2) AS avg_departure_delay
    FROM
        flight_features
    WHERE
        Year >= 2005
        AND Cancelled = 0
    GROUP BY
        Origin, Dest, flight_hour, DayOfWeek
    HAVING
        COUNT(*) >= 20
),

base_results AS (
    -- Main Result: Optimal Departure Windows
    SELECT
    COALESCE(r.origin_airport, h.origin_airport) AS origin_airport,
    COALESCE(r.destination_airport, h.destination_airport) AS destination_airport,
    COALESCE(r.hour_of_day, h.flight_hour) AS hour_of_day,
    COALESCE(r.day_of_week,
        CASE h.DayOfWeek
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
            WHEN 7 THEN 'Sunday'
            ELSE 'Unknown'
        END
    ) AS day_of_week,
    -- Real-time metrics
    r.total_flights AS realtime_flight_count,
    r.on_time_rate_pct AS realtime_on_time_rate_pct,
    r.cancellation_rate_pct AS realtime_cancellation_rate_pct,
    r.avg_arrival_delay AS realtime_avg_delay,
    -- Historical metrics
    h.total_flights AS historical_flight_count,
    h.on_time_rate_pct AS historical_on_time_rate_pct,
    h.cancellation_rate_pct AS historical_cancellation_rate_pct,
    h.avg_arrival_delay AS historical_avg_delay,
    -- Combined metrics (weighted average)
    COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) AS combined_on_time_rate_pct,
    COALESCE(r.cancellation_rate_pct, h.cancellation_rate_pct) AS combined_cancellation_rate_pct,
    -- Window quality recommendation
    CASE
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 85 
             AND COALESCE(r.cancellation_rate_pct, h.cancellation_rate_pct) < 2 THEN 'OPTIMAL'
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 75 
             AND COALESCE(r.cancellation_rate_pct, h.cancellation_rate_pct) < 5 THEN 'GOOD'
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 65 THEN 'ACCEPTABLE'
        ELSE 'AVOID'
    END AS window_quality,
    -- Recommendation text
    CASE
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 85 THEN 
            CONCAT('Best time to fly - ', CAST(COALESCE(r.hour_of_day, h.flight_hour) AS VARCHAR), ':00 has ', 
                   CAST(ROUND(COALESCE(r.on_time_rate_pct, h.on_time_rate_pct)) AS VARCHAR), '% on-time rate')
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 75 THEN 
            CONCAT('Good option - ', CAST(COALESCE(r.hour_of_day, h.flight_hour) AS VARCHAR), ':00 typically reliable')
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 65 THEN 
            CONCAT('Acceptable - ', CAST(COALESCE(r.hour_of_day, h.flight_hour) AS VARCHAR), ':00 may have delays')
        ELSE 
            CONCAT('Avoid if possible - ', CAST(COALESCE(r.hour_of_day, h.flight_hour) AS VARCHAR), 
                   ':00 has high delay risk')
    END AS recommendation
FROM
    realtime_hourly_performance r
FULL OUTER JOIN
    historical_hourly_performance h
    ON r.origin_airport = h.origin_airport
    AND r.destination_airport = h.destination_airport
    AND r.hour_of_day = h.flight_hour
    AND r.day_of_week = CASE h.DayOfWeek
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
        WHEN 7 THEN 'Sunday'
        ELSE 'Unknown'
    END
WHERE
    COALESCE(r.total_flights, h.total_flights) >= 10
)
SELECT * FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY origin_airport, destination_airport
            ORDER BY combined_on_time_rate_pct DESC, combined_cancellation_rate_pct ASC
        ) AS reliability_rank
    FROM base_results
) ranked
WHERE reliability_rank <= 5  -- Top 5 hours per route
ORDER BY
    origin_airport, destination_airport, reliability_rank;

