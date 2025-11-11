-- ============================================================================
-- Buffer Recommendations Query
-- ============================================================================
-- Operational tool to identify routes needing buffer increases
-- Provides actionable recommendations for schedule planning

WITH route_buffer_analysis AS (
    SELECT
        Origin AS origin_airport,
        Dest AS destination_airport,
        airport_type AS origin_airport_type,
        route_type,
        COUNT(*) AS total_flights,
        
        -- Buffer adequacy metrics
        SUM(CASE WHEN buffer_adequacy_category = 'insufficient' THEN 1 ELSE 0 END) AS insufficient_count,
        SUM(CASE WHEN buffer_adequacy_category = 'marginal' THEN 1 ELSE 0 END) AS marginal_count,
        SUM(CASE WHEN buffer_adequacy_category = 'adequate' THEN 1 ELSE 0 END) AS adequate_count,
        SUM(CASE WHEN buffer_adequacy_category = 'generous' THEN 1 ELSE 0 END) AS generous_count,
        
        ROUND(100.0 * SUM(CASE WHEN buffer_adequacy_category = 'insufficient' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS insufficient_pct,
        
        -- Current vs recommended buffers
        ROUND(AVG(TRY_CAST(turnaround_time_minutes AS DOUBLE)), 0) AS current_avg_buffer_minutes,
        ROUND(AVG(recommended_buffer_minutes), 0) AS recommended_avg_buffer_minutes,
        ROUND(AVG(TRY_CAST(buffer_shortfall_minutes AS DOUBLE)), 0) AS avg_shortfall_minutes,
        ROUND(MAX(buffer_shortfall_minutes), 0) AS max_shortfall_minutes,
        
        -- Delay metrics
        ROUND(AVG(p90_arrival_delay), 0) AS p90_historical_delay,
        ROUND(AVG(TRY_CAST(arrdelay AS DOUBLE)), 2) AS avg_actual_delay,
        
        -- Cascade metrics
        SUM(CASE WHEN cascade_occurred = 1 THEN 1 ELSE 0 END) AS cascade_count,
        ROUND(100.0 * SUM(CASE WHEN cascade_occurred = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cascade_rate_pct,
        
        -- High risk flags
        SUM(high_risk_rotation) AS high_risk_rotation_count,
        
        -- Flight characteristics
        ROUND(AVG(TRY_CAST(distance AS DOUBLE)), 0) AS avg_distance_miles,
        COUNT(DISTINCT UniqueCarrier) AS carriers_operating
        
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 2005
        AND cancelled = 0
        AND TailNum IS NOT NULL
        AND turnaround_time_minutes IS NOT NULL
        AND buffer_adequacy_category IS NOT NULL
    GROUP BY
        Origin, Dest, airport_type, route_type
    HAVING
        COUNT(*) >= 1  -- Lowered threshold
)

-- Main recommendations: Routes needing buffer increases
SELECT
    origin_airport,
    destination_airport,
    route_type,
    origin_airport_type,
    total_flights,
    
    -- Problem severity
    insufficient_count,
    insufficient_pct,
    cascade_rate_pct,
    high_risk_rotation_count,
    
    -- Buffer recommendations
    current_avg_buffer_minutes,
    recommended_avg_buffer_minutes,
    avg_shortfall_minutes,
    max_shortfall_minutes,
    
    -- Supporting metrics
    p90_historical_delay,
    avg_actual_delay,
    cascade_count,
    avg_distance_miles,
    carriers_operating,
    
    -- Priority score (weighted combination of factors)
    ROUND(
        (insufficient_pct * 0.4) +                    -- 40% weight: % of flights with insufficient buffer
        (cascade_rate_pct * 0.3) +                    -- 30% weight: cascade rate
        (avg_shortfall_minutes * 0.2) +               -- 20% weight: buffer shortfall
        (high_risk_rotation_count * 0.1)              -- 10% weight: high risk rotations
    , 2) AS priority_score,
    
    -- Action recommendation
    CASE
        WHEN insufficient_pct > 50 AND cascade_rate_pct > 40 THEN 'CRITICAL - Immediate Action Required'
        WHEN insufficient_pct > 30 AND cascade_rate_pct > 25 THEN 'HIGH - Review Within 30 Days'
        WHEN insufficient_pct > 20 OR cascade_rate_pct > 15 THEN 'MEDIUM - Monitor and Plan Adjustment'
        ELSE 'LOW - Continue Monitoring'
    END AS action_priority,
    
    -- Recommended buffer increase
    CASE
        WHEN avg_shortfall_minutes >= 20 THEN CONCAT('Add ', CAST(CEIL(avg_shortfall_minutes / 5) * 5 AS VARCHAR), ' minutes')
        WHEN avg_shortfall_minutes >= 10 THEN 'Add 10-15 minutes'
        WHEN avg_shortfall_minutes >= 5 THEN 'Add 5-10 minutes'
        ELSE 'Monitor closely'
    END AS recommended_action

FROM
    route_buffer_analysis

WHERE
    -- Focus on problematic routes
    (insufficient_pct > 0 OR cascade_rate_pct > 0)
    AND insufficient_count >= 0

ORDER BY
    priority_score DESC,
    insufficient_pct DESC,
    cascade_rate_pct DESC,
    avg_shortfall_minutes DESC

LIMIT 100;
