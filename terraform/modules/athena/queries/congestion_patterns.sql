-- CONGESTION PATTERNS ANALYSIS
-- Rewritten to use actual available schema from flights table
-- Original purpose: Identify congestion patterns by hour and route
-- Simplified: Uses flight count and delays as congestion proxy (no traffic_level column)

WITH hourly_route_traffic AS (
    SELECT
        origin_airport,
        destination_airport,
        hour_of_day,
        day_of_week,
        flight_date,
        COUNT(*) AS flight_count,
        SUM(CASE WHEN arrival_delay_minutes > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(AVG(departure_delay_minutes), 2) AS avg_departure_delay,
        MAX(arrival_delay_minutes) AS max_delay,
        SUM(CASE WHEN is_cancelled = true THEN 1 ELSE 0 END) AS cancelled_flights,
        ROUND(AVG(taxi_out_minutes), 2) AS avg_taxi_out,
        ROUND(AVG(taxi_in_minutes), 2) AS avg_taxi_in
    FROM "flight-delays-dev-db".flights
    WHERE FROM_ISO8601_TIMESTAMP(timestamp) >= CURRENT_TIMESTAMP - INTERVAL '7' DAY
    GROUP BY origin_airport, destination_airport, hour_of_day, day_of_week, flight_date
),

origin_congestion AS (
    SELECT
        origin_airport,
        hour_of_day,
        day_of_week,
        SUM(flight_count) AS total_departures,
        SUM(delayed_flights) AS total_delayed,
        ROUND(100.0 * SUM(delayed_flights) / NULLIF(SUM(flight_count), 0), 2) AS delay_rate_pct,
        ROUND(AVG(avg_departure_delay), 2) AS avg_dep_delay,
        ROUND(AVG(avg_taxi_out), 2) AS avg_taxi_out_time,
        MAX(max_delay) AS worst_delay
    FROM hourly_route_traffic
    GROUP BY origin_airport, hour_of_day, day_of_week
    HAVING SUM(flight_count) >= 5  -- Require minimum sample
),

destination_congestion AS (
    SELECT
        destination_airport,
        hour_of_day,
        day_of_week,
        SUM(flight_count) AS total_arrivals,
        SUM(delayed_flights) AS total_delayed,
        ROUND(100.0 * SUM(delayed_flights) / NULLIF(SUM(flight_count), 0), 2) AS delay_rate_pct,
        ROUND(AVG(avg_arrival_delay), 2) AS avg_arr_delay,
        ROUND(AVG(avg_taxi_in), 2) AS avg_taxi_in_time,
        MAX(max_delay) AS worst_delay
    FROM hourly_route_traffic
    GROUP BY destination_airport, hour_of_day, day_of_week
    HAVING SUM(flight_count) >= 5
),

congestion_score AS (
    SELECT
        origin_airport AS airport,
        'DEPARTURE' AS congestion_type,
        hour_of_day,
        day_of_week,
        total_departures AS flight_volume,
        delay_rate_pct,
        avg_dep_delay AS avg_delay,
        avg_taxi_out_time AS avg_taxi_time,
        worst_delay,
        -- Congestion score: flight volume * delay rate * avg delay
        ROUND((total_departures * delay_rate_pct * COALESCE(avg_dep_delay, 0)) / 100.0, 2) AS congestion_score
    FROM origin_congestion
    
    UNION ALL
    
    SELECT
        destination_airport AS airport,
        'ARRIVAL' AS congestion_type,
        hour_of_day,
        day_of_week,
        total_arrivals AS flight_volume,
        delay_rate_pct,
        avg_arr_delay AS avg_delay,
        avg_taxi_in_time AS avg_taxi_time,
        worst_delay,
        ROUND((total_arrivals * delay_rate_pct * COALESCE(avg_arr_delay, 0)) / 100.0, 2) AS congestion_score
    FROM destination_congestion
)

-- FINAL OUTPUT: Congestion patterns ranked by severity
SELECT
    airport,
    congestion_type,
    hour_of_day,
    day_of_week,
    flight_volume,
    delay_rate_pct,
    avg_delay,
    avg_taxi_time,
    worst_delay,
    congestion_score,
    CASE
        WHEN congestion_score >= 100 THEN 'SEVERE'
        WHEN congestion_score >= 50 THEN 'HIGH'
        WHEN congestion_score >= 20 THEN 'MODERATE'
        ELSE 'LIGHT'
    END AS congestion_level,
    CASE
        WHEN hour_of_day BETWEEN 6 AND 9 THEN 'MORNING_PEAK'
        WHEN hour_of_day BETWEEN 17 AND 20 THEN 'EVENING_PEAK'
        WHEN hour_of_day BETWEEN 10 AND 16 THEN 'MIDDAY'
        ELSE 'OFF_PEAK'
    END AS time_period
FROM congestion_score
WHERE congestion_score > 0
ORDER BY congestion_score DESC, flight_volume DESC
LIMIT 100;
