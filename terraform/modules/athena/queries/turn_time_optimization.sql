-- TURN TIME OPTIMIZATION
-- Rewritten to use actual available schema from flights table
-- Original purpose: Aircraft turnaround time optimization
-- Simplified: Uses tail_number to track aircraft (no flight_id available)
-- Focus: Analyze turnaround efficiency by aircraft and airport

WITH flight_sequence AS (
    SELECT
        tail_number,
        origin_airport,
        destination_airport,
        carrier,
        flight_number,
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
        -- Convert time strings to minutes since midnight for calculation
        TRY(
            CAST(SUBSTR(actual_arrival_time, 1, 2) AS INT) * 60 + 
            CAST(SUBSTR(actual_arrival_time, 4, 2) AS INT)
        ) AS arrival_minutes,
        TRY(
            CAST(SUBSTR(actual_departure_time, 1, 2) AS INT) * 60 + 
            CAST(SUBSTR(actual_departure_time, 4, 2) AS INT)
        ) AS departure_minutes,
        TRY(
            CAST(SUBSTR(scheduled_departure_time, 1, 2) AS INT) * 60 + 
            CAST(SUBSTR(scheduled_departure_time, 4, 2) AS INT)
        ) AS scheduled_departure_minutes,
        ROW_NUMBER() OVER (
            PARTITION BY tail_number, flight_date
            ORDER BY scheduled_departure_time
        ) AS flight_sequence_number
    FROM "flight-delays-dev-db".flights
    WHERE FROM_ISO8601_TIMESTAMP(timestamp) >= CURRENT_TIMESTAMP - INTERVAL '90' DAY
        AND tail_number IS NOT NULL
        AND tail_number != ''
        AND is_cancelled = false
),

-- Calculate turnaround time between consecutive flights
turnaround_times AS (
    SELECT
        f1.tail_number,
        f1.destination_airport AS turnaround_airport,
        f1.carrier,
        f1.flight_date,
        f1.flight_number AS first_flight,
        f2.flight_number AS second_flight,
        f1.actual_arrival_time AS first_arrival,
        f2.actual_departure_time AS second_departure,
        f1.arrival_delay_minutes AS first_flight_delay,
        f2.departure_delay_minutes AS second_flight_delay,
        f1.cascade_risk AS first_cascade_risk,
        f2.cascade_risk AS second_cascade_risk,
        -- Turnaround time in minutes
        CASE
            WHEN f2.departure_minutes >= f1.arrival_minutes THEN
                f2.departure_minutes - f1.arrival_minutes
            ELSE
                -- Handle overnight turnaround (next day)
                (1440 - f1.arrival_minutes) + f2.departure_minutes
        END AS turnaround_time_minutes,
        -- Scheduled turnaround time
        CASE
            WHEN f2.scheduled_departure_minutes >= f1.arrival_minutes THEN
                f2.scheduled_departure_minutes - f1.arrival_minutes
            ELSE
                (1440 - f1.arrival_minutes) + f2.scheduled_departure_minutes
        END AS scheduled_turnaround_minutes
    FROM flight_sequence f1
    INNER JOIN flight_sequence f2
        ON f1.tail_number = f2.tail_number
        AND f1.flight_date = f2.flight_date
        AND f1.destination_airport = f2.origin_airport
        AND f2.flight_sequence_number = f1.flight_sequence_number + 1
    WHERE f1.arrival_minutes IS NOT NULL
        AND f2.departure_minutes IS NOT NULL
),

-- Analyze turnaround efficiency
turnaround_analysis AS (
    SELECT
        turnaround_airport,
        carrier,
        COUNT(*) AS total_turnarounds,
        ROUND(AVG(turnaround_time_minutes), 2) AS avg_turnaround_minutes,
        ROUND(AVG(scheduled_turnaround_minutes), 2) AS avg_scheduled_turnaround,
        ROUND(STDDEV(turnaround_time_minutes), 2) AS stddev_turnaround,
        ROUND(MIN(turnaround_time_minutes), 2) AS min_turnaround_minutes,
        ROUND(MAX(turnaround_time_minutes), 2) AS max_turnaround_minutes,
        ROUND(APPROX_PERCENTILE(turnaround_time_minutes, 0.50), 2) AS median_turnaround,
        ROUND(APPROX_PERCENTILE(turnaround_time_minutes, 0.90), 2) AS p90_turnaround,
        SUM(CASE WHEN turnaround_time_minutes < 45 THEN 1 ELSE 0 END) AS quick_turnarounds,
        SUM(CASE WHEN turnaround_time_minutes > 120 THEN 1 ELSE 0 END) AS slow_turnarounds,
        SUM(CASE WHEN second_flight_delay > 15 THEN 1 ELSE 0 END) AS delayed_second_flights,
        SUM(CASE WHEN second_cascade_risk = true THEN 1 ELSE 0 END) AS cascade_after_turnaround,
        ROUND(AVG(CASE WHEN second_flight_delay > 15 THEN turnaround_time_minutes END), 2) AS avg_turnaround_when_delayed
    FROM turnaround_times
    GROUP BY turnaround_airport, carrier
    HAVING COUNT(*) >= 1  -- Require minimum sample
),

-- Calculate efficiency metrics
turnaround_efficiency AS (
    SELECT
        *,
        ROUND(100.0 * quick_turnarounds / NULLIF(total_turnarounds, 0), 2) AS quick_turnaround_rate_pct,
        ROUND(100.0 * slow_turnarounds / NULLIF(total_turnarounds, 0), 2) AS slow_turnaround_rate_pct,
        ROUND(100.0 * delayed_second_flights / NULLIF(total_turnarounds, 0), 2) AS second_flight_delay_rate_pct,
        ROUND(100.0 * cascade_after_turnaround / NULLIF(total_turnarounds, 0), 2) AS cascade_rate_pct,
        -- Efficiency score: lower is better (combines speed and consistency)
        ROUND((avg_turnaround_minutes / 60.0) + (COALESCE(stddev_turnaround, 0) / 100.0), 2) AS efficiency_score,
        CASE
            WHEN avg_turnaround_minutes <= 45 THEN 'EXCELLENT'
            WHEN avg_turnaround_minutes <= 60 THEN 'GOOD'
            WHEN avg_turnaround_minutes <= 90 THEN 'FAIR'
            ELSE 'POOR'
        END AS efficiency_rating
    FROM turnaround_analysis
),

-- Identify optimization opportunities
optimization_opportunities AS (
    SELECT
        *,
        -- Calculate potential time savings
        CASE
            WHEN avg_turnaround_minutes > median_turnaround + 15 THEN
                ROUND(avg_turnaround_minutes - median_turnaround, 2)
            ELSE 0
        END AS potential_time_savings_minutes,
        CASE
            WHEN slow_turnaround_rate_pct > 20 THEN 'HIGH_PRIORITY'
            WHEN slow_turnaround_rate_pct > 10 THEN 'MEDIUM_PRIORITY'
            ELSE 'LOW_PRIORITY'
        END AS optimization_priority
    FROM turnaround_efficiency
)

-- FINAL OUTPUT: Turnaround optimization recommendations
-- NOTE: This query requires aircraft with consecutive flights (same tail_number arriving then departing from same airport)
-- If no data is returned, it means there are no consecutive flights in the dataset
SELECT
    turnaround_airport,
    carrier,
    total_turnarounds,
    avg_turnaround_minutes,
    avg_scheduled_turnaround,
    median_turnaround,
    p90_turnaround,
    stddev_turnaround,
    min_turnaround_minutes,
    max_turnaround_minutes,
    quick_turnaround_rate_pct,
    slow_turnaround_rate_pct,
    second_flight_delay_rate_pct,
    cascade_rate_pct,
    avg_turnaround_when_delayed,
    efficiency_score,
    efficiency_rating,
    potential_time_savings_minutes,
    optimization_priority,
    CASE
        WHEN cascade_rate_pct >= 30 THEN 'Focus on preventing cascade delays'
        WHEN slow_turnaround_rate_pct >= 25 THEN 'Reduce slow turnarounds (>2 hours)'
        WHEN stddev_turnaround >= 30 THEN 'Improve turnaround consistency'
        WHEN avg_turnaround_minutes > avg_scheduled_turnaround + 15 THEN 'Align actual with scheduled times'
        ELSE 'Maintain current efficiency'
    END AS optimization_recommendation
FROM optimization_opportunities
ORDER BY optimization_priority DESC, efficiency_score DESC, total_turnarounds DESC
LIMIT 100;
