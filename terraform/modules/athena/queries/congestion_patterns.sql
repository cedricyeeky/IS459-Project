-- ============================================================================
-- BQ1: Congestion Patterns & Ground Operations Improvement Targets
-- ============================================================================
-- Combines real-time flight data with historical Gold layer data
-- Output: Congestion patterns and ground operations improvement targets

WITH realtime_congestion AS (
    -- Real-time congestion metrics from mock API
    SELECT
        origin_airport,
        destination_airport,
        hour_of_day,
        day_of_week,
        flight_date,
        origin_traffic_level,
        destination_traffic_level,
        status,
        arrival_delay_minutes,
        departure_delay_minutes,
        is_delayed,
        timestamp AS realtime_timestamp
    FROM
        realtime_flights
    WHERE
        timestamp >= CURRENT_TIMESTAMP - INTERVAL '7' DAY
        AND status IN ('scheduled', 'boarding', 'departed', 'in_air', 'landed', 'arrived')
),

hourly_congestion AS (
    -- Aggregate congestion by hour and day
    SELECT
        origin_airport,
        hour_of_day,
        day_of_week,
        origin_traffic_level,
        COUNT(*) AS current_flight_count,
        SUM(CASE WHEN status IN ('scheduled', 'boarding', 'departed') THEN 1 ELSE 0 END) AS scheduled_departures,
        SUM(CASE WHEN status IN ('landed', 'arrived') THEN 1 ELSE 0 END) AS arrivals,
        SUM(CASE WHEN is_delayed THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN is_delayed THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(AVG(departure_delay_minutes), 2) AS avg_departure_delay,
        -- Traffic level distribution
        MAX(CASE WHEN origin_traffic_level = 'high' THEN 1 ELSE 0 END) AS has_high_traffic,
        MAX(CASE WHEN origin_traffic_level = 'medium' THEN 1 ELSE 0 END) AS has_medium_traffic
    FROM
        realtime_congestion
    GROUP BY
        origin_airport, hour_of_day, day_of_week, origin_traffic_level
),

historical_congestion AS (
    -- Historical congestion patterns from Gold layer
    SELECT
        Origin AS origin_airport,
        hour_category,
        DayOfWeek,
        COUNT(*) AS total_flights,
        ROUND(AVG(TaxiOut), 2) AS avg_taxi_out_minutes,
        ROUND(AVG(TaxiIn), 2) AS avg_taxi_in_minutes,
        ROUND(AVG(turnaround_time_minutes), 2) AS avg_turnaround,
        ROUND(AVG(DepDelay), 2) AS avg_departure_delay,
        ROUND(AVG(ArrDelay), 2) AS avg_arrival_delay,
        SUM(CASE WHEN DepDelay > 15 THEN 1 ELSE 0 END) AS delayed_departures,
        SUM(CASE WHEN TaxiOut > 20 THEN 1 ELSE 0 END) AS long_taxi_out,
        SUM(CASE WHEN TaxiIn > 15 THEN 1 ELSE 0 END) AS long_taxi_in,
        COUNT(*) / 60.0 AS flights_per_hour  -- Assuming 60-minute window
    FROM
        flight_features
    WHERE
        Year >= 2005
        AND Cancelled = 0
        AND Origin IS NOT NULL
    GROUP BY
        Origin, hour_category, DayOfWeek
    HAVING
        COUNT(*) >= 20
)

-- Main Result: Congestion Patterns & Improvement Targets
SELECT
    COALESCE(r.origin_airport, h.origin_airport) AS airport,
    COALESCE(r.hour_of_day, 
        CASE h.hour_category
            WHEN 'night' THEN 2
            WHEN 'early_morning' THEN 7
            WHEN 'morning' THEN 10
            WHEN 'late_morning' THEN 13
            WHEN 'afternoon' THEN 16
            WHEN 'evening' THEN 20
            ELSE 12
        END
    ) AS hour_of_day,
    COALESCE(r.day_of_week, 
        CASE h.DayOfWeek
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
            WHEN 7 THEN 'Sunday'
            ELSE 'Unknown'
        END
    ) AS day_of_day,
    -- Real-time metrics
    r.current_flight_count,
    r.scheduled_departures,
    r.arrivals,
    r.delayed_flights,
    r.delay_rate_pct AS realtime_delay_rate_pct,
    r.avg_arrival_delay AS realtime_avg_delay,
    r.origin_traffic_level,
    -- Historical metrics
    h.flights_per_hour AS historical_flights_per_hour,
    h.avg_taxi_out_minutes,
    h.avg_taxi_in_minutes,
    h.avg_turnaround,
    h.avg_departure_delay AS historical_avg_departure_delay,
    h.avg_arrival_delay AS historical_avg_arrival_delay,
    h.long_taxi_out,
    ROUND(100.0 * h.long_taxi_out / NULLIF(h.total_flights, 0), 2) AS long_taxi_out_pct,
    h.long_taxi_in,
    ROUND(100.0 * h.long_taxi_in / NULLIF(h.total_flights, 0), 2) AS long_taxi_in_pct,
    -- Congestion score
    ROUND(
        (COALESCE(r.current_flight_count / 60.0, h.flights_per_hour) / 10.0) * 30 +  -- Flight volume component
        (COALESCE(h.avg_taxi_out_minutes, 0) / 30.0) * 25 +  -- Taxi out component
        (COALESCE(h.avg_turnaround, 0) / 60.0) * 25 +  -- Turnaround component
        (COALESCE(r.delay_rate_pct, h.delayed_departures * 100.0 / NULLIF(h.total_flights, 0), 0) / 100.0) * 20  -- Delay rate component
    , 2) AS congestion_score,
    -- Congestion level
    CASE
        WHEN COALESCE(r.current_flight_count / 60.0, h.flights_per_hour) > 15 
             AND COALESCE(r.delay_rate_pct, 0) > 30 THEN 'CRITICAL - Immediate Action'
        WHEN COALESCE(r.current_flight_count / 60.0, h.flights_per_hour) > 12 
             AND COALESCE(r.delay_rate_pct, 0) > 20 THEN 'HIGH - Schedule Review'
        WHEN COALESCE(r.current_flight_count / 60.0, h.flights_per_hour) > 10 THEN 'MEDIUM - Monitor'
        ELSE 'LOW'
    END AS congestion_level,
    -- Improvement targets
    CASE
        WHEN h.avg_taxi_out_minutes > 20 THEN CONCAT('Reduce taxi-out by ', CAST(ROUND(h.avg_taxi_out_minutes - 15) AS VARCHAR), ' min')
        ELSE 'Taxi-out acceptable'
    END AS taxi_out_target,
    CASE
        WHEN h.avg_turnaround > 60 THEN CONCAT('Reduce turnaround by ', CAST(ROUND(h.avg_turnaround - 45) AS VARCHAR), ' min')
        ELSE 'Turnaround acceptable'
    END AS turnaround_target,
    CASE
        WHEN r.delay_rate_pct > 30 THEN 'Implement ground delay program'
        WHEN r.delay_rate_pct > 20 THEN 'Review gate assignments'
        ELSE 'Monitor closely'
    END AS operational_target
FROM
    hourly_congestion r
FULL OUTER JOIN
    historical_congestion h
    ON r.origin_airport = h.origin_airport
    AND r.hour_of_day = CASE h.hour_category
        WHEN 'night' THEN 2
        WHEN 'early_morning' THEN 7
        WHEN 'morning' THEN 10
        WHEN 'late_morning' THEN 13
        WHEN 'afternoon' THEN 16
        WHEN 'evening' THEN 20
        ELSE 12
    END
WHERE
    COALESCE(r.current_flight_count / 60.0, h.flights_per_hour) > 8  -- Focus on busy periods
    OR r.delay_rate_pct > 15
ORDER BY
    congestion_score DESC,
    COALESCE(r.current_flight_count / 60.0, h.flights_per_hour) DESC
LIMIT 500;

