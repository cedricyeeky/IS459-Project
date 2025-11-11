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
        COUNT(DISTINCT carrier_code) AS carrier_count
    FROM
        realtime_flights
    WHERE
        timestamp >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
    GROUP BY
        origin_airport, destination_airport
    HAVING
        COUNT(DISTINCT carrier_code) >= 2  -- At least 2 carriers
),

realtime_carrier_performance AS (
    -- Real-time carrier performance from mock API
    SELECT
        carrier_code,
        carrier_name,
        origin_airport,
        destination_airport,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN on_time THEN 1 ELSE 0 END) AS on_time_flights,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS cancelled_flights,
        ROUND(100.0 * SUM(CASE WHEN on_time THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(carrier_reliability_score), 3) AS avg_reliability_score,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.8), 2) AS p80_arrival_delay
    FROM
        realtime_flights
    WHERE
        timestamp >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
    GROUP BY
        carrier_code, carrier_name, origin_airport, destination_airport
    HAVING
        COUNT(*) >= 20
),

historical_carrier_performance AS (
    -- Historical carrier performance from Gold layer
    SELECT
        UniqueCarrier AS carrier_code,
        Origin AS origin_airport,
        Dest AS destination_airport,
        COUNT(*) AS total_flights,
        SUM(on_time_flag) AS on_time_flights,
        SUM(cancelled_flag) AS cancelled_flights,
        ROUND(100.0 * SUM(on_time_flag) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(cancelled_flag) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(reliability_score), 3) AS avg_reliability_score,
        ROUND(AVG(ArrDelay), 2) AS avg_arrival_delay,
        ROUND(PERCENTILE_APPROX(ArrDelay, 0.8, 100), 2) AS p80_arrival_delay
    FROM
        flight_features
    WHERE
        Year >= 2005
    GROUP BY
        UniqueCarrier, Origin, Dest
    HAVING
        COUNT(*) >= 50
),

carrier_route_performance AS (
    -- Combine real-time and historical performance
    SELECT
        cr.origin_airport,
        cr.destination_airport,
        COALESCE(r.carrier_code, h.carrier_code) AS carrier_code,
        r.carrier_name,
        -- Real-time metrics
        r.total_flights AS realtime_flight_count,
        r.on_time_rate_pct AS realtime_on_time_rate_pct,
        r.cancellation_rate_pct AS realtime_cancellation_rate_pct,
        r.avg_reliability_score AS realtime_reliability_score,
        r.avg_arrival_delay AS realtime_avg_delay,
        r.p80_arrival_delay AS realtime_p80_delay,
        -- Historical metrics
        h.total_flights AS historical_flight_count,
        h.on_time_rate_pct AS historical_on_time_rate_pct,
        h.cancellation_rate_pct AS historical_cancellation_rate_pct,
        h.avg_reliability_score AS historical_reliability_score,
        h.avg_arrival_delay AS historical_avg_delay,
        h.p80_arrival_delay AS historical_p80_delay,
        -- Combined score (weighted: 60% historical, 40% real-time)
        ROUND(
            COALESCE(h.avg_reliability_score, 0.5) * 0.6 +
            COALESCE(r.avg_reliability_score, 0.5) * 0.4,
        3) AS combined_reliability_score,
        COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) AS combined_on_time_rate_pct
    FROM
        competitive_routes cr
    INNER JOIN
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
    carrier_name,
    realtime_flight_count,
    historical_flight_count,
    combined_on_time_rate_pct,
    realtime_on_time_rate_pct,
    historical_on_time_rate_pct,
    realtime_cancellation_rate_pct,
    historical_cancellation_rate_pct,
    combined_reliability_score,
    realtime_reliability_score,
    historical_reliability_score,
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

