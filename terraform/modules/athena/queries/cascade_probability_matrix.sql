-- ============================================================================
-- BQ1: Cascade Probability Matrix & High-Risk Station Identification
-- ============================================================================
-- Combines real-time flight data with historical Gold layer data
-- Output: Cascade probability matrices and high-risk station identification

WITH realtime_cascades AS (
    -- Real-time cascade detection from mock API
    SELECT
        origin_airport,
        destination_airport,
        tail_number,
        carrier_code,
        flight_date,
        hour_of_day,
        cascade_risk,
        arrival_delay_minutes,
        departure_delay_minutes,
        status,
        timestamp AS realtime_timestamp
    FROM
        realtime_flights
    WHERE
        cascade_risk = true
        AND timestamp >= CURRENT_TIMESTAMP - INTERVAL '24' HOUR
),

historical_cascade_metrics AS (
    -- Historical cascade patterns from Gold layer
    SELECT
        Origin AS origin_airport,
        Dest AS destination_airport,
        UniqueCarrier AS carrier_code,
        Year,
        Month,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN cascade_occurred = 1 THEN 1 ELSE 0 END) AS cascade_events,
        ROUND(100.0 * SUM(CASE WHEN cascade_occurred = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cascade_rate_pct,
        ROUND(AVG(delay_cascaded), 2) AS avg_delay_cascaded_minutes,
        ROUND(AVG(turnaround_time_minutes), 2) AS avg_turnaround_minutes
    FROM
        flight_features
    WHERE
        Year >= 2005
        AND Cancelled = 0
        AND TailNum IS NOT NULL
    GROUP BY
        Origin, Dest, UniqueCarrier, Year, Month
    HAVING
        COUNT(*) >= 50
),

airport_cascade_risk AS (
    -- High-risk station identification
    SELECT
        COALESCE(r.origin_airport, h.origin_airport) AS airport_code,
        COUNT(DISTINCT r.flight_id) AS realtime_cascade_events,
        COUNT(DISTINCT h.origin_airport || h.destination_airport || h.carrier_code) AS historical_cascade_routes,
        ROUND(AVG(h.cascade_rate_pct), 2) AS avg_historical_cascade_rate,
        ROUND(AVG(r.arrival_delay_minutes), 2) AS avg_realtime_delay,
        MAX(r.arrival_delay_minutes) AS max_realtime_delay
    FROM
        realtime_cascades r
    FULL OUTER JOIN
        historical_cascade_metrics h
        ON r.origin_airport = h.origin_airport
    GROUP BY
        COALESCE(r.origin_airport, h.origin_airport)
)

-- Main Result: Cascade Probability Matrix & High-Risk Stations
SELECT
    'Cascade Probability Matrix' AS analysis_type,
    h.origin_airport AS source_airport,
    h.destination_airport AS destination_airport,
    h.carrier_code,
    h.cascade_rate_pct AS historical_cascade_probability_pct,
    COUNT(DISTINCT r.flight_id) AS realtime_cascade_count,
    ROUND(AVG(r.arrival_delay_minutes), 2) AS avg_realtime_cascade_delay,
    h.avg_delay_cascaded_minutes AS avg_historical_cascade_delay,
    h.avg_turnaround_minutes,
    h.total_flights AS historical_sample_size,
    -- Risk level classification
    CASE
        WHEN h.cascade_rate_pct > 50 OR COUNT(DISTINCT r.flight_id) > 10 THEN 'CRITICAL'
        WHEN h.cascade_rate_pct > 30 OR COUNT(DISTINCT r.flight_id) > 5 THEN 'HIGH'
        WHEN h.cascade_rate_pct > 15 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS risk_level
FROM
    historical_cascade_metrics h
LEFT JOIN
    realtime_cascades r
    ON h.origin_airport = r.origin_airport
    AND h.destination_airport = r.destination_airport
    AND h.carrier_code = r.carrier_code
GROUP BY
    h.origin_airport, h.destination_airport, h.carrier_code,
    h.cascade_rate_pct, h.avg_delay_cascaded_minutes, h.avg_turnaround_minutes, h.total_flights

UNION ALL

-- High-Risk Station Summary
SELECT
    'High-Risk Station' AS analysis_type,
    a.airport_code AS source_airport,
    NULL AS destination_airport,
    NULL AS carrier_code,
    a.avg_historical_cascade_rate AS historical_cascade_probability_pct,
    a.realtime_cascade_events AS realtime_cascade_count,
    a.avg_realtime_delay AS avg_realtime_cascade_delay,
    NULL AS avg_historical_cascade_delay,
    NULL AS avg_turnaround_minutes,
    NULL AS historical_sample_size,
    CASE
        WHEN a.avg_historical_cascade_rate > 40 OR a.realtime_cascade_events > 10 THEN 'CRITICAL'
        WHEN a.avg_historical_cascade_rate > 30 OR a.realtime_cascade_events > 5 THEN 'HIGH'
        WHEN a.avg_historical_cascade_rate > 20 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS risk_level
FROM
    airport_cascade_risk a
WHERE
    a.avg_historical_cascade_rate > 15 OR a.realtime_cascade_events > 0

ORDER BY
    risk_level DESC,
    historical_cascade_probability_pct DESC,
    realtime_cascade_count DESC
LIMIT 500;

