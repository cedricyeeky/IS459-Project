-- ============================================================================
-- Query 4: HOW do delays cascade?
-- ============================================================================
-- Analyzes cascade mechanics: aircraft rotation tracking, buffer effectiveness
-- This query answers: "HOW do delays propagate through aircraft rotations?"

-- Aircraft Cascade Analysis
WITH aircraft_cascades AS (
    SELECT
        TailNum AS aircraft,
        flight_date,
        Origin,
        Dest,
        COUNT(*) AS flights_per_day,
        SUM(CASE WHEN cascade_trigger_flag = 1 THEN 1 ELSE 0 END) AS cascade_triggers,
        SUM(CASE WHEN cascade_follow_flag = 1 THEN 1 ELSE 0 END) AS cascade_events,
        SUM(CASE WHEN TRY_CAST(delay_cascaded AS DOUBLE) > 0 THEN 1 ELSE 0 END) AS cascaded_flights,
        MAX(cascade_depth) AS max_cascade_depth,
        ROUND(AVG(cascade_depth), 2) AS avg_cascade_depth,
        ROUND(SUM(TRY_CAST(delay_cascaded AS DOUBLE)), 2) AS total_delay_cascaded_minutes,
        ROUND(AVG(TRY_CAST(turnaround_time_minutes AS DOUBLE)), 2) AS avg_turnaround_minutes,
        ROUND(AVG(TRY_CAST(buffer_adequacy_ratio AS DOUBLE)), 2) AS avg_buffer_adequacy,
        COUNT(CASE WHEN buffer_adequacy_category = 'insufficient' THEN 1 END) AS insufficient_buffer_flights,
        COUNT(CASE WHEN buffer_adequacy_category = 'adequate' THEN 1 END) AS adequate_buffer_flights,
        SUM(CASE WHEN recovered_from_delay = 1 THEN 1 ELSE 0 END) AS recovery_events
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 2005
        AND cancelled = 0
        AND TailNum IS NOT NULL
        AND is_valid_rotation = 1
    GROUP BY
        TailNum, flight_date, Origin, Dest
),

-- Buffer Effectiveness Analysis
buffer_effectiveness AS (
    SELECT
        buffer_adequacy_category,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN cascade_occurred = 1 THEN 1 ELSE 0 END) AS cascade_count,
        ROUND(100.0 * SUM(CASE WHEN cascade_occurred = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cascade_rate_pct,
        ROUND(AVG(TRY_CAST(turnaround_time_minutes AS DOUBLE)), 2) AS avg_turnaround_minutes,
        ROUND(AVG(TRY_CAST(delay_cascaded AS DOUBLE)), 2) AS avg_delay_cascaded_minutes,
        ROUND(AVG(TRY_CAST(buffer_shortfall_minutes AS DOUBLE)), 2) AS avg_buffer_shortfall
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 2005
        AND cancelled = 0
        AND buffer_adequacy_category IS NOT NULL
        AND is_valid_rotation = 1
    GROUP BY
        buffer_adequacy_category
),

-- Cascade Depth Distribution
cascade_depth_distribution AS (
    SELECT
        cascade_depth,
        COUNT(*) AS flight_count,
        ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS pct_of_total,
        ROUND(AVG(TRY_CAST(arrdelay AS DOUBLE)), 2) AS avg_delay_minutes,
        ROUND(AVG(TRY_CAST(delay_cascaded AS DOUBLE)), 2) AS avg_delay_cascaded
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 2005
        AND cancelled = 0
        AND cascade_depth > 0
    GROUP BY
        cascade_depth
),

-- Recovery Analysis (how quickly aircraft return to on-time)
recovery_analysis AS (
    SELECT
        cascade_depth AS depth_before_recovery,
        COUNT(*) AS recovery_count,
        ROUND(AVG(TRY_CAST(turnaround_time_minutes AS DOUBLE)), 2) AS avg_recovery_turnaround,
        ROUND(AVG(TRY_CAST(buffer_adequacy_ratio AS DOUBLE)), 2) AS avg_buffer_at_recovery
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 2005
        AND cancelled = 0
        AND recovered_from_delay = 1
        AND cascade_depth > 0
    GROUP BY
        cascade_depth
)

-- Main Result: Aircraft Cascade Performance
SELECT
    'Aircraft Cascades' AS analysis_type,
    aircraft,
    flight_date,
    Origin AS first_origin,
    Dest AS last_dest,
    flights_per_day,
    cascade_triggers,
    cascade_events,
    cascaded_flights,
    ROUND(100.0 * cascade_events / NULLIF(cascade_triggers, 0), 2) AS cascade_propagation_pct,
    max_cascade_depth,
    avg_cascade_depth,
    total_delay_cascaded_minutes,
    avg_turnaround_minutes,
    avg_buffer_adequacy,
    insufficient_buffer_flights,
    adequate_buffer_flights,
    recovery_events,
    CASE 
        WHEN avg_buffer_adequacy < 0.7 THEN 'Critical'
        WHEN avg_buffer_adequacy < 0.9 THEN 'Warning'
        ELSE 'Acceptable'
    END AS buffer_status
FROM
    aircraft_cascades
WHERE
    flights_per_day >= 1  -- Focus on any aircraft with flights
ORDER BY
    cascade_events DESC,
    max_cascade_depth DESC,
    total_delay_cascaded_minutes DESC
LIMIT 500;
