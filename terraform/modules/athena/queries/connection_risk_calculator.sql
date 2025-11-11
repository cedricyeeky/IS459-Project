-- CONNECTION RISK CALCULATOR
-- Rewritten to use actual available schema from flights table
-- Original purpose: Multi-leg connection risk assessment
-- Simplified: Single-flight buffer analysis (cannot track multi-flight without flight_id)
-- Focus: Analyze turnaround buffer adequacy for same aircraft at destination airports

WITH flight_timing AS (
    SELECT
        origin_airport,
        destination_airport,
        carrier,
        flight_number,
        tail_number,
        flight_date,
        scheduled_departure_time,
        actual_departure_time,
        scheduled_arrival_time,
        actual_arrival_time,
        departure_delay_minutes,
        arrival_delay_minutes,
        is_cancelled,
        cascade_risk,
        timestamp,
        -- Calculate scheduled vs actual duration
        TRY(
            CAST(
                (CAST(SUBSTR(scheduled_arrival_time, 1, 2) AS INT) * 60 + 
                 CAST(SUBSTR(scheduled_arrival_time, 4, 2) AS INT)) -
                (CAST(SUBSTR(scheduled_departure_time, 1, 2) AS INT) * 60 + 
                 CAST(SUBSTR(scheduled_departure_time, 4, 2) AS INT))
                AS DOUBLE
            )
        ) AS scheduled_duration_minutes,
        TRY(
            CAST(
                (CAST(SUBSTR(actual_arrival_time, 1, 2) AS INT) * 60 + 
                 CAST(SUBSTR(actual_arrival_time, 4, 2) AS INT)) -
                (CAST(SUBSTR(actual_departure_time, 1, 2) AS INT) * 60 + 
                 CAST(SUBSTR(actual_departure_time, 4, 2) AS INT))
                AS DOUBLE
            )
        ) AS actual_duration_minutes
    FROM "flight-delays-dev-db".flights
    WHERE FROM_ISO8601_TIMESTAMP(timestamp) >= CURRENT_TIMESTAMP - INTERVAL '7' DAY
        AND is_cancelled = false
),

-- Analyze buffer adequacy by route
route_buffer_analysis AS (
    SELECT
        origin_airport,
        destination_airport,
        COUNT(*) AS total_flights,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(STDDEV(arrival_delay_minutes), 2) AS stddev_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.50), 2) AS p50_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.75), 2) AS p75_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.90), 2) AS p90_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.95), 2) AS p95_arrival_delay,
        SUM(CASE WHEN arrival_delay_minutes <= 15 THEN 1 ELSE 0 END) AS on_time_arrivals,
        SUM(CASE WHEN arrival_delay_minutes > 60 THEN 1 ELSE 0 END) AS severe_delays,
        SUM(CASE WHEN cascade_risk = true THEN 1 ELSE 0 END) AS cascade_events,
        ROUND(100.0 * SUM(CASE WHEN cascade_risk = true THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cascade_rate_pct
    FROM flight_timing
    GROUP BY origin_airport, destination_airport
    HAVING COUNT(*) >= 10
),

-- Calculate recommended connection buffer times
buffer_recommendations AS (
    SELECT
        origin_airport,
        destination_airport,
        total_flights,
        avg_arrival_delay,
        stddev_arrival_delay,
        p50_arrival_delay,
        p75_arrival_delay,
        p90_arrival_delay,
        p95_arrival_delay,
        on_time_arrivals,
        severe_delays,
        cascade_events,
        cascade_rate_pct,
        -- Recommended buffer: Base 45 min + p90 delay + safety margin
        ROUND(45 + COALESCE(p90_arrival_delay, 0) + COALESCE(stddev_arrival_delay, 0) * 0.5, 0) AS recommended_buffer_minutes,
        -- Minimum safe buffer: Base 30 min + p75 delay
        ROUND(30 + COALESCE(p75_arrival_delay, 0), 0) AS minimum_safe_buffer_minutes,
        -- Conservative buffer for high-risk: Base 60 min + p95 delay
        ROUND(60 + COALESCE(p95_arrival_delay, 0), 0) AS conservative_buffer_minutes,
        ROUND(100.0 * on_time_arrivals / NULLIF(total_flights, 0), 2) AS on_time_arrival_rate_pct
    FROM route_buffer_analysis
),

-- Calculate connection risk levels
connection_risk_assessment AS (
    SELECT
        *,
        -- Risk score: weighted combination of delay factors
        ROUND(
            (avg_arrival_delay * 0.3) +
            (COALESCE(stddev_arrival_delay, 0) * 0.2) +
            (COALESCE(p90_arrival_delay, 0) * 0.3) +
            (cascade_rate_pct * 0.2),
            2
        ) AS connection_risk_score,
        CASE
            WHEN cascade_rate_pct >= 30 OR p90_arrival_delay >= 60 THEN 'CRITICAL'
            WHEN cascade_rate_pct >= 15 OR p90_arrival_delay >= 30 THEN 'HIGH'
            WHEN cascade_rate_pct >= 5 OR p90_arrival_delay >= 15 THEN 'MEDIUM'
            ELSE 'LOW'
        END AS connection_risk_level
    FROM buffer_recommendations
)

-- FINAL OUTPUT: Connection risk assessment with buffer recommendations
SELECT
    origin_airport,
    destination_airport,
    total_flights,
    on_time_arrival_rate_pct,
    avg_arrival_delay,
    stddev_arrival_delay,
    p50_arrival_delay,
    p75_arrival_delay,
    p90_arrival_delay,
    p95_arrival_delay,
    cascade_events,
    cascade_rate_pct,
    minimum_safe_buffer_minutes,
    recommended_buffer_minutes,
    conservative_buffer_minutes,
    connection_risk_score,
    connection_risk_level,
    CASE
        WHEN on_time_arrival_rate_pct >= 85 THEN 'EXCELLENT'
        WHEN on_time_arrival_rate_pct >= 70 THEN 'GOOD'
        WHEN on_time_arrival_rate_pct >= 50 THEN 'FAIR'
        ELSE 'POOR'
    END AS connection_reliability
FROM connection_risk_assessment
ORDER BY connection_risk_score DESC, total_flights DESC
LIMIT 100;
