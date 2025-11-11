-- ============================================================================
-- BQ2: Carrier Comparison Rankings on Competitive Routes
-- ============================================================================
-- Combines real-time flight data with historical Gold layer data
-- Output: Carrier comparison rankings on competitive routes

WITH competitive_routes AS (
    -- Identify routes with multiple carriers
    SELECT
        origin_airport,
        destination_airport,
        COUNT(DISTINCT carrier) AS carrier_count
    FROM
        "flight-delays-dev-db".flights
    WHERE
        FROM_ISO8601_TIMESTAMP(timestamp) >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
    GROUP BY
        origin_airport, destination_airport
    HAVING
        COUNT(DISTINCT carrier) >= 1  -- At least 1 carrier (show all routes)
),

realtime_carrier_performance AS (
    -- Real-time carrier performance from mock API
    SELECT
        carrier AS carrier_code,
        origin_airport,
        destination_airport,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN arrival_delay_minutes <= 15 THEN 1 ELSE 0 END) AS on_time_flights,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS cancelled_flights,
        ROUND(100.0 * SUM(CASE WHEN arrival_delay_minutes <= 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.8), 2) AS p80_arrival_delay
    FROM
        "flight-delays-dev-db".flights
    WHERE
        FROM_ISO8601_TIMESTAMP(timestamp) >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
    GROUP BY
        carrier, origin_airport, destination_airport
    HAVING
        COUNT(*) >= 1
),

historical_carrier_performance AS (
    -- Historical carrier performance from Gold layer
    SELECT
        UniqueCarrier AS carrier_code,
        Origin AS origin_airport,
        Dest AS destination_airport,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) <= 15 THEN 1 ELSE 0 END) AS on_time_flights,
        SUM(cancelled) AS cancelled_flights,
        ROUND(100.0 * SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) <= 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(cancelled) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(TRY_CAST(arrdelay AS DOUBLE)), 2) AS avg_arrival_delay,
        ROUND(APPROX_PERCENTILE(TRY_CAST(arrdelay AS DOUBLE), 0.8), 2) AS p80_arrival_delay
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 1987
    GROUP BY
        UniqueCarrier, Origin, Dest
    HAVING
        COUNT(*) >= 1
),

carrier_route_performance AS (
    -- Combine real-time and historical performance
    SELECT
        cr.origin_airport,
        cr.destination_airport,
        COALESCE(r.carrier_code, h.carrier_code) AS carrier_code,
        -- Real-time metrics
        r.total_flights AS realtime_flight_count,
        r.on_time_rate_pct AS realtime_on_time_rate_pct,
        r.cancellation_rate_pct AS realtime_cancellation_rate_pct,
        r.avg_arrival_delay AS realtime_avg_delay,
        r.p80_arrival_delay AS realtime_p80_delay,
        -- Historical metrics
        h.total_flights AS historical_flight_count,
        h.on_time_rate_pct AS historical_on_time_rate_pct,
        h.cancellation_rate_pct AS historical_cancellation_rate_pct,
        h.avg_arrival_delay AS historical_avg_delay,
        h.p80_arrival_delay AS historical_p80_delay,
        -- Combined score (weighted: 60% historical, 40% real-time on-time rate)
        ROUND(
            COALESCE(h.on_time_rate_pct, 0.0) * 0.6 +
            COALESCE(r.on_time_rate_pct, 0.0) * 0.4,
        2) AS combined_on_time_rate_pct
    FROM
        competitive_routes cr
    LEFT JOIN
        realtime_carrier_performance r
        ON cr.origin_airport = r.origin_airport
        AND cr.destination_airport = r.destination_airport
    FULL OUTER JOIN
        historical_carrier_performance h
        ON r.carrier_code = h.carrier_code
        AND r.origin_airport = h.origin_airport
        AND r.destination_airport = h.destination_airport
)

-- Main Result: Carrier Comparison Rankings
SELECT
    origin_airport,
    destination_airport,
    carrier_code,
    realtime_flight_count,
    historical_flight_count,
    combined_on_time_rate_pct,
    realtime_on_time_rate_pct,
    historical_on_time_rate_pct,
    realtime_cancellation_rate_pct,
    historical_cancellation_rate_pct,
    realtime_avg_delay,
    historical_avg_delay,
    realtime_p80_delay,
    historical_p80_delay,
    -- Ranking within route
    ROW_NUMBER() OVER (
        PARTITION BY origin_airport, destination_airport 
        ORDER BY combined_on_time_rate_pct DESC, 
                 realtime_cancellation_rate_pct ASC, 
                 realtime_avg_delay ASC
    ) AS carrier_rank,
    -- Performance category
    CASE
        WHEN ROW_NUMBER() OVER (
            PARTITION BY origin_airport, destination_airport 
            ORDER BY combined_on_time_rate_pct DESC, realtime_cancellation_rate_pct ASC
        ) = 1 THEN 'BEST'
        WHEN ROW_NUMBER() OVER (
            PARTITION BY origin_airport, destination_airport 
            ORDER BY combined_on_time_rate_pct DESC, realtime_cancellation_rate_pct ASC
        ) <= 2 THEN 'TOP_TIER'
        ELSE 'COMPETITIVE'
    END AS performance_category
FROM
    carrier_route_performance
ORDER BY
    origin_airport, destination_airport, carrier_rank;

