-- ============================================================================
-- BQ2: Connection Risk Calculator with Minimum Buffer Recommendations
-- ============================================================================
-- Combines real-time flight data with historical Gold layer data
-- Output: Connection risk calculator with minimum buffer recommendations

WITH realtime_connections AS (
    -- Real-time connection analysis from mock API
    SELECT
        f1.flight_id AS first_flight_id,
        f2.flight_id AS second_flight_id,
        f1.carrier_code AS first_carrier,
        f2.carrier_code AS second_carrier,
        f1.origin_airport,
        f1.destination_airport AS connection_airport,
        f2.destination_airport AS final_destination,
        f1.tail_number,
        f1.actual_arrival,
        f2.scheduled_departure,
        f1.arrival_delay_minutes AS first_flight_delay,
        f2.departure_delay_minutes AS second_flight_delay,
        f1.cascade_risk AS first_flight_cascade_risk,
        f1.is_delayed AS first_flight_delayed,
        f2.is_cancelled AS second_flight_cancelled,
        -- Calculate connection time
        TIMESTAMPDIFF(MINUTE,
            CAST(f1.actual_arrival AS TIMESTAMP),
            CAST(f2.scheduled_departure AS TIMESTAMP)
        ) AS connection_time_minutes
    FROM
        realtime_flights f1
    INNER JOIN
        realtime_flights f2
        ON f1.destination_airport = f2.origin_airport
        AND f1.tail_number = f2.tail_number  -- Same aircraft
        AND DATE(f1.flight_date) = DATE(f2.flight_date)
        AND CAST(f1.actual_arrival AS TIMESTAMP) < CAST(f2.scheduled_departure AS TIMESTAMP)
    WHERE
        f1.timestamp >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
        AND f2.timestamp >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
        AND f1.status IN ('arrived', 'landed')
        AND f2.status IN ('scheduled', 'boarding')
),

historical_connections AS (
    -- Historical connection analysis from Gold layer
    SELECT
        f1.Origin AS origin_airport,
        f1.Dest AS connection_airport,
        f2.Dest AS final_destination,
        f1.UniqueCarrier AS first_carrier,
        f2.UniqueCarrier AS second_carrier,
        COUNT(*) AS total_connections,
        -- Calculate connection time (simplified - using CRS times)
        ROUND(AVG(
            (f2.CRSDepTime - f1.CRSArrTime) / 100 * 60 + 
            (f2.CRSDepTime - f1.CRSArrTime) % 100
        ), 0) AS avg_connection_time_minutes,
        -- Connection success metrics
        SUM(CASE 
            WHEN f1.ArrDelay <= 15 AND f2.DepDelay <= 15 THEN 1 
            ELSE 0 
        END) AS successful_connections,
        SUM(CASE 
            WHEN f1.ArrDelay > 15 OR f2.Cancelled = 1 THEN 1 
            ELSE 0 
        END) AS missed_connections,
        -- Delay statistics
        ROUND(AVG(f1.ArrDelay), 2) AS avg_first_flight_arrival_delay,
        ROUND(PERCENTILE_APPROX(f1.ArrDelay, 0.8, 100), 2) AS p80_first_flight_delay,
        ROUND(PERCENTILE_APPROX(f1.ArrDelay, 0.95, 100), 2) AS p95_first_flight_delay,
        ROUND(AVG(f2.DepDelay), 2) AS avg_second_flight_departure_delay,
        -- Connection success rate
        ROUND(100.0 * SUM(CASE 
            WHEN f1.ArrDelay <= 15 AND f2.DepDelay <= 15 THEN 1 
            ELSE 0 
        END) / NULLIF(COUNT(*), 0), 2) AS connection_success_rate_pct
    FROM
        flight_features f1
    INNER JOIN
        flight_features f2
        ON f1.Dest = f2.Origin
        AND f1.TailNum = f2.TailNum
        AND f1.flight_date = f2.flight_date
        AND f1.CRSArrTime < f2.CRSDepTime
    WHERE
        f1.Year >= 2005
        AND f1.Cancelled = 0
        AND f2.Cancelled = 0
    GROUP BY
        f1.Origin, f1.Dest, f2.Dest, f1.UniqueCarrier, f2.UniqueCarrier
    HAVING
        COUNT(*) >= 20
)

-- Main Result: Connection Risk Calculator
SELECT
    COALESCE(r.origin_airport, h.origin_airport) AS origin_airport,
    COALESCE(r.connection_airport, h.connection_airport) AS connection_airport,
    COALESCE(r.final_destination, h.final_destination) AS final_destination,
    COALESCE(r.first_carrier, h.first_carrier) AS first_carrier,
    COALESCE(r.second_carrier, h.second_carrier) AS second_carrier,
    -- Real-time metrics
    COUNT(DISTINCT r.first_flight_id) AS realtime_connection_count,
    ROUND(AVG(r.connection_time_minutes), 0) AS avg_realtime_connection_time,
    SUM(CASE 
        WHEN r.first_flight_delayed = true OR r.second_flight_cancelled = true THEN 1 
        ELSE 0 
    END) AS realtime_missed_connections,
    ROUND(AVG(r.first_flight_delay), 2) AS avg_realtime_first_flight_delay,
    SUM(CASE WHEN r.first_flight_cascade_risk = true THEN 1 ELSE 0 END) AS realtime_cascade_risk_count,
    -- Historical metrics
    h.total_connections AS historical_connection_count,
    h.avg_connection_time_minutes AS historical_avg_connection_time,
    h.connection_success_rate_pct AS historical_success_rate_pct,
    h.avg_first_flight_arrival_delay AS historical_avg_first_delay,
    h.p80_first_flight_delay,
    h.p95_first_flight_delay,
    h.avg_second_flight_departure_delay,
    h.missed_connections AS historical_missed_connections,
    -- Recommended minimum buffer
    GREATEST(
        COALESCE(h.p95_first_flight_delay, 30) + 30,  -- 95th percentile delay + 30 min safety
        COALESCE(h.avg_connection_time_minutes, 60) + 15  -- Current average + 15 min
    ) AS recommended_minimum_buffer_minutes,
    -- Connection risk level
    CASE
        WHEN COALESCE(h.connection_success_rate_pct, 
            100.0 * (COUNT(DISTINCT r.first_flight_id) - SUM(CASE WHEN r.first_flight_delayed = true OR r.second_flight_cancelled = true THEN 1 ELSE 0 END)) / 
            NULLIF(COUNT(DISTINCT r.first_flight_id), 0)) >= 90 THEN 'LOW_RISK'
        WHEN COALESCE(h.connection_success_rate_pct, 
            100.0 * (COUNT(DISTINCT r.first_flight_id) - SUM(CASE WHEN r.first_flight_delayed = true OR r.second_flight_cancelled = true THEN 1 ELSE 0 END)) / 
            NULLIF(COUNT(DISTINCT r.first_flight_id), 0)) >= 75 THEN 'MEDIUM_RISK'
        WHEN COALESCE(h.connection_success_rate_pct, 
            100.0 * (COUNT(DISTINCT r.first_flight_id) - SUM(CASE WHEN r.first_flight_delayed = true OR r.second_flight_cancelled = true THEN 1 ELSE 0 END)) / 
            NULLIF(COUNT(DISTINCT r.first_flight_id), 0)) >= 60 THEN 'HIGH_RISK'
        ELSE 'VERY_HIGH_RISK'
    END AS connection_risk_level,
    -- Connection recommendation
    CASE
        WHEN COALESCE(h.connection_success_rate_pct, 
            100.0 * (COUNT(DISTINCT r.first_flight_id) - SUM(CASE WHEN r.first_flight_delayed = true OR r.second_flight_cancelled = true THEN 1 ELSE 0 END)) / 
            NULLIF(COUNT(DISTINCT r.first_flight_id), 0)) < 70 THEN 'AVOID - Too risky'
        WHEN COALESCE(r.connection_time_minutes, h.avg_connection_time_minutes) < 
             (COALESCE(h.p95_first_flight_delay, 30) + 30) THEN 
            CONCAT('INCREASE buffer to ', 
                   CAST(GREATEST(COALESCE(h.p95_first_flight_delay, 30) + 30, 
                                 COALESCE(h.avg_connection_time_minutes, 60) + 15) AS VARCHAR), 
                   ' min')
        WHEN COALESCE(h.connection_success_rate_pct, 
            100.0 * (COUNT(DISTINCT r.first_flight_id) - SUM(CASE WHEN r.first_flight_delayed = true OR r.second_flight_cancelled = true THEN 1 ELSE 0 END)) / 
            NULLIF(COUNT(DISTINCT r.first_flight_id), 0)) >= 85 THEN 'ACCEPTABLE - Current buffer sufficient'
        ELSE 'MONITOR - Consider longer buffer'
    END AS connection_recommendation
FROM
    realtime_connections r
FULL OUTER JOIN
    historical_connections h
    ON r.origin_airport = h.origin_airport
    AND r.connection_airport = h.connection_airport
    AND r.final_destination = h.final_destination
    AND r.first_carrier = h.first_carrier
    AND r.second_carrier = h.second_carrier
GROUP BY
    COALESCE(r.origin_airport, h.origin_airport),
    COALESCE(r.connection_airport, h.connection_airport),
    COALESCE(r.final_destination, h.final_destination),
    COALESCE(r.first_carrier, h.first_carrier),
    COALESCE(r.second_carrier, h.second_carrier),
    h.total_connections, h.avg_connection_time_minutes, h.connection_success_rate_pct,
    h.avg_first_flight_arrival_delay, h.p80_first_flight_delay, h.p95_first_flight_delay,
    h.avg_second_flight_departure_delay, h.missed_connections
HAVING
    COALESCE(COUNT(DISTINCT r.first_flight_id), h.total_connections) >= 5
ORDER BY
    connection_risk_level ASC,
    COALESCE(h.connection_success_rate_pct, 
        100.0 * (COUNT(DISTINCT r.first_flight_id) - SUM(CASE WHEN r.first_flight_delayed = true OR r.second_flight_cancelled = true THEN 1 ELSE 0 END)) / 
        NULLIF(COUNT(DISTINCT r.first_flight_id), 0)) ASC,
    realtime_missed_connections DESC
LIMIT 1000;

