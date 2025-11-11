-- ============================================================================
-- BQ1: Turn Time Optimization Recommendations with Cost-Benefit Analysis
-- ============================================================================
-- Combines real-time flight data with historical Gold layer data
-- Output: Turn time optimization recommendations with cost-benefit analysis

WITH realtime_turnaround AS (
    -- Real-time turnaround analysis from mock API
    SELECT
        tail_number,
        origin_airport,
        destination_airport,
        carrier_code,
        flight_date,
        actual_arrival,
        scheduled_departure,
        arrival_delay_minutes,
        departure_delay_minutes,
        -- Calculate real-time turnaround
        TIMESTAMPDIFF(MINUTE, 
            CAST(actual_arrival AS TIMESTAMP), 
            CAST(scheduled_departure AS TIMESTAMP)
        ) AS realtime_turnaround_minutes,
        cascade_risk,
        status
    FROM
        realtime_flights
    WHERE
        actual_arrival IS NOT NULL
        AND scheduled_departure IS NOT NULL
        AND status IN ('landed', 'arrived', 'scheduled', 'boarding')
        AND timestamp >= CURRENT_TIMESTAMP - INTERVAL '7' DAY
),

historical_buffer_analysis AS (
    -- Historical buffer recommendations from Gold layer
    SELECT
        Origin AS origin_airport,
        Dest AS destination_airport,
        UniqueCarrier AS carrier_code,
        hour_category,
        COUNT(*) AS total_flights,
        ROUND(AVG(turnaround_time_minutes), 0) AS current_avg_turnaround,
        ROUND(AVG(recommended_buffer_minutes), 0) AS recommended_turnaround,
        ROUND(AVG(buffer_shortfall_minutes), 0) AS avg_shortfall,
        ROUND(MAX(buffer_shortfall_minutes), 0) AS max_shortfall,
        SUM(CASE WHEN cascade_occurred = 1 THEN 1 ELSE 0 END) AS cascade_count,
        ROUND(100.0 * SUM(CASE WHEN cascade_occurred = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cascade_rate_pct,
        ROUND(AVG(delay_cascaded), 2) AS avg_delay_cascaded,
        ROUND(AVG(p90_arrival_delay), 0) AS p90_historical_delay
    FROM
        flight_features
    WHERE
        Year >= 2005
        AND Cancelled = 0
        AND turnaround_time_minutes IS NOT NULL
        AND recommended_buffer_minutes IS NOT NULL
    GROUP BY
        Origin, Dest, UniqueCarrier, hour_category
    HAVING
        COUNT(*) >= 50
),

turn_time_analysis AS (
    -- Combine real-time and historical data
    SELECT
        COALESCE(r.origin_airport, h.origin_airport) AS origin_airport,
        COALESCE(r.destination_airport, h.destination_airport) AS destination_airport,
        COALESCE(r.carrier_code, h.carrier_code) AS carrier_code,
        h.hour_category,
        h.total_flights,
        h.current_avg_turnaround,
        h.recommended_turnaround,
        (h.recommended_turnaround - h.current_avg_turnaround) AS minutes_to_add,
        h.avg_shortfall,
        h.max_shortfall,
        h.cascade_count,
        h.cascade_rate_pct,
        h.avg_delay_cascaded,
        h.p90_historical_delay,
        -- Real-time metrics
        COUNT(DISTINCT r.flight_id) AS realtime_flight_count,
        ROUND(AVG(r.realtime_turnaround_minutes), 0) AS avg_realtime_turnaround,
        SUM(CASE WHEN r.cascade_risk = true THEN 1 ELSE 0 END) AS realtime_cascade_count,
        ROUND(AVG(r.arrival_delay_minutes), 2) AS avg_realtime_arrival_delay
    FROM
        historical_buffer_analysis h
    LEFT JOIN
        realtime_turnaround r
        ON h.origin_airport = r.origin_airport
        AND h.destination_airport = r.destination_airport
        AND h.carrier_code = r.carrier_code
    GROUP BY
        COALESCE(r.origin_airport, h.origin_airport),
        COALESCE(r.destination_airport, h.destination_airport),
        COALESCE(r.carrier_code, h.carrier_code),
        h.hour_category, h.total_flights, h.current_avg_turnaround,
        h.recommended_turnaround, h.avg_shortfall, h.max_shortfall,
        h.cascade_count, h.cascade_rate_pct, h.avg_delay_cascaded, h.p90_historical_delay
)

-- Main Result: Turn Time Optimization with Cost-Benefit
SELECT
    origin_airport,
    destination_airport,
    carrier_code,
    hour_category,
    total_flights,
    current_avg_turnaround,
    recommended_turnaround,
    minutes_to_add,
    avg_shortfall,
    max_shortfall,
    cascade_count,
    cascade_rate_pct,
    avg_delay_cascaded,
    realtime_flight_count,
    avg_realtime_turnaround,
    realtime_cascade_count,
    -- Cost estimates (simplified)
    total_flights * 150 AS current_operational_cost,  -- $150 per flight
    total_flights * minutes_to_add * 2 AS additional_buffer_cost,  -- $2 per minute
    -- Benefit: Reduced cascades (estimated $500 per avoided cascade)
    cascade_count * 500 AS current_cascade_cost,
    ROUND(cascade_count * 0.5 * 500, 0) AS estimated_avoided_cascade_cost,  -- Assume 50% reduction
    -- Net Benefit
    (ROUND(cascade_count * 0.5 * 500, 0) - (total_flights * minutes_to_add * 2)) AS net_benefit,
    -- ROI
    ROUND(
        ((ROUND(cascade_count * 0.5 * 500, 0) - (total_flights * minutes_to_add * 2)) / 
         NULLIF((total_flights * minutes_to_add * 2), 0)) * 100
    , 2) AS roi_pct,
    -- Recommendation
    CASE
        WHEN (ROUND(cascade_count * 0.5 * 500, 0) - (total_flights * minutes_to_add * 2)) > 10000 THEN 'HIGH ROI - Implement'
        WHEN (ROUND(cascade_count * 0.5 * 500, 0) - (total_flights * minutes_to_add * 2)) > 0 THEN 'POSITIVE ROI - Consider'
        ELSE 'NEGATIVE ROI - Review'
    END AS recommendation,
    -- Priority score
    ROUND(
        (avg_shortfall * 0.3) +
        (cascade_rate_pct * 0.3) +
        (CASE WHEN realtime_cascade_count > 0 THEN 30 ELSE 0 END) +
        (CASE WHEN avg_realtime_turnaround < recommended_turnaround THEN 20 ELSE 0 END)
    , 2) AS priority_score
FROM
    turn_time_analysis
WHERE
    avg_shortfall > 5  -- Only routes with significant shortfall
    OR realtime_cascade_count > 0  -- Or with real-time cascades
ORDER BY
    priority_score DESC,
    net_benefit DESC,
    roi_pct DESC
LIMIT 200;

