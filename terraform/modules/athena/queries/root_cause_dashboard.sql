-- ROOT CAUSE DASHBOARD
-- Rewritten to use actual available schema from flights table
-- Original purpose: Root cause analysis with delay categorization
-- Simplified: Delay magnitude analysis (no delay_reason column available)
-- Focus: Pattern-based delay analysis by severity, time, and location

WITH flight_delays AS (
    SELECT
        origin_airport,
        destination_airport,
        carrier,
        flight_number,
        tail_number,
        flight_date,
        hour_of_day,
        day_of_week,
        month,
        departure_delay_minutes,
        arrival_delay_minutes,
        is_cancelled,
        is_diverted,
        cascade_risk,
        air_time_minutes,
        distance_miles,
        taxi_out_minutes,
        taxi_in_minutes,
        timestamp,
        -- Categorize by delay severity
        CASE
            WHEN arrival_delay_minutes <= 0 THEN 'EARLY'
            WHEN arrival_delay_minutes <= 15 THEN 'ON_TIME'
            WHEN arrival_delay_minutes <= 30 THEN 'MINOR_DELAY'
            WHEN arrival_delay_minutes <= 60 THEN 'MODERATE_DELAY'
            WHEN arrival_delay_minutes <= 120 THEN 'MAJOR_DELAY'
            ELSE 'SEVERE_DELAY'
        END AS delay_severity,
        -- Categorize operational phase where delay occurred
        CASE
            WHEN departure_delay_minutes > 15 AND arrival_delay_minutes <= departure_delay_minutes THEN 'DEPARTURE_PHASE'
            WHEN arrival_delay_minutes > departure_delay_minutes + 10 THEN 'AIRBORNE_PHASE'
            WHEN taxi_out_minutes > 20 OR taxi_in_minutes > 15 THEN 'TAXI_PHASE'
            ELSE 'NORMAL_OPERATIONS'
        END AS delay_phase,
        -- Time period classification
        CASE
            WHEN hour_of_day BETWEEN 5 AND 8 THEN 'EARLY_MORNING'
            WHEN hour_of_day BETWEEN 9 AND 11 THEN 'LATE_MORNING'
            WHEN hour_of_day BETWEEN 12 AND 16 THEN 'AFTERNOON'
            WHEN hour_of_day BETWEEN 17 AND 20 THEN 'EVENING'
            ELSE 'NIGHT'
        END AS time_period
    FROM "flight-delays-dev-db".flights
    WHERE FROM_ISO8601_TIMESTAMP(timestamp) >= CURRENT_TIMESTAMP - INTERVAL '7' DAY
),

delay_severity_breakdown AS (
    SELECT
        delay_severity,
        COUNT(*) AS flight_count,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_delay,
        ROUND(AVG(departure_delay_minutes), 2) AS avg_departure_delay,
        SUM(CASE WHEN is_cancelled = true THEN 1 ELSE 0 END) AS cancelled_count,
        SUM(CASE WHEN cascade_risk = true THEN 1 ELSE 0 END) AS cascade_count
    FROM flight_delays
    GROUP BY delay_severity
),

delay_phase_breakdown AS (
    SELECT
        delay_phase,
        COUNT(*) AS flight_count,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_delay,
        ROUND(AVG(taxi_out_minutes), 2) AS avg_taxi_out,
        ROUND(AVG(taxi_in_minutes), 2) AS avg_taxi_in
    FROM flight_delays
    WHERE arrival_delay_minutes > 15  -- Only delayed flights
    GROUP BY delay_phase
),

airport_delay_patterns AS (
    SELECT
        origin_airport,
        COUNT(*) AS total_departures,
        SUM(CASE WHEN arrival_delay_minutes > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN arrival_delay_minutes > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(CASE WHEN arrival_delay_minutes > 15 THEN arrival_delay_minutes END), 2) AS avg_delay_when_delayed,
        SUM(CASE WHEN is_cancelled = true THEN 1 ELSE 0 END) AS cancellations,
        SUM(CASE WHEN cascade_risk = true THEN 1 ELSE 0 END) AS cascade_events,
        -- Identify dominant delay pattern
        CASE
            WHEN AVG(CASE WHEN arrival_delay_minutes > 15 THEN taxi_out_minutes END) > 25 THEN 'TAXI_OUT_CONGESTION'
            WHEN AVG(CASE WHEN arrival_delay_minutes > 15 THEN departure_delay_minutes END) > 30 THEN 'DEPARTURE_DELAYS'
            WHEN ROUND(100.0 * SUM(CASE WHEN cascade_risk = true THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) > 20 THEN 'CASCADE_PRONE'
            ELSE 'GENERAL_DELAYS'
        END AS dominant_pattern
    FROM flight_delays
    GROUP BY origin_airport
    HAVING COUNT(*) >= 10
),

carrier_delay_patterns AS (
    SELECT
        carrier,
        COUNT(*) AS total_flights,
        ROUND(100.0 * SUM(CASE WHEN arrival_delay_minutes > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_delay,
        SUM(CASE WHEN is_cancelled = true THEN 1 ELSE 0 END) AS cancellations,
        ROUND(100.0 * SUM(CASE WHEN is_cancelled = true THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct
    FROM flight_delays
    GROUP BY carrier
    HAVING COUNT(*) >= 10
),

time_period_delays AS (
    SELECT
        time_period,
        hour_of_day,
        COUNT(*) AS flight_count,
        ROUND(100.0 * SUM(CASE WHEN arrival_delay_minutes > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_delay
    FROM flight_delays
    GROUP BY time_period, hour_of_day
)

-- FINAL OUTPUT: Root cause dashboard summary
SELECT
    'SEVERITY_BREAKDOWN' AS metric_category,
    delay_severity AS metric_value,
    CAST(flight_count AS VARCHAR) AS count_value,
    pct_of_total AS percentage,
    avg_delay AS avg_delay_minutes,
    CAST(NULL AS DOUBLE) AS secondary_metric
FROM delay_severity_breakdown

UNION ALL

SELECT
    'DELAY_PHASE' AS metric_category,
    delay_phase AS metric_value,
    CAST(flight_count AS VARCHAR) AS count_value,
    pct_of_total AS percentage,
    avg_delay AS avg_delay_minutes,
    avg_taxi_out AS secondary_metric
FROM delay_phase_breakdown

UNION ALL

SELECT
    'AIRPORT_PATTERN' AS metric_category,
    origin_airport || ' - ' || dominant_pattern AS metric_value,
    CAST(total_departures AS VARCHAR) AS count_value,
    delay_rate_pct AS percentage,
    avg_delay_when_delayed AS avg_delay_minutes,
    CAST(cascade_events AS DOUBLE) AS secondary_metric
FROM (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY delay_rate_pct DESC) AS rn
    FROM airport_delay_patterns
) ranked_airports
WHERE rn <= 20

UNION ALL

SELECT
    'CARRIER_PERFORMANCE' AS metric_category,
    carrier AS metric_value,
    CAST(total_flights AS VARCHAR) AS count_value,
    delay_rate_pct AS percentage,
    avg_delay AS avg_delay_minutes,
    cancellation_rate_pct AS secondary_metric
FROM carrier_delay_patterns

UNION ALL

SELECT
    'TIME_PERIOD' AS metric_category,
    time_period || ' (Hour ' || CAST(hour_of_day AS VARCHAR) || ')' AS metric_value,
    CAST(flight_count AS VARCHAR) AS count_value,
    delay_rate_pct AS percentage,
    avg_delay AS avg_delay_minutes,
    CAST(NULL AS DOUBLE) AS secondary_metric
FROM time_period_delays
WHERE delay_rate_pct > 20

ORDER BY metric_category, percentage DESC
LIMIT 100;
