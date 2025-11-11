-- ============================================================================
-- BQ1: Root Cause Dashboard - Delay Composition Analysis
-- ============================================================================
-- Combines real-time flight data, weather data, and historical Gold layer
-- Output: Root cause dashboards showing delay composition

WITH realtime_delays AS (
    -- Real-time delay data from mock API
    SELECT
        origin_airport,
        destination_airport,
        carrier_code,
        flight_date,
        hour_of_day,
        is_delayed,
        is_cancelled,
        arrival_delay_minutes,
        departure_delay_minutes,
        delay_reason,
        status,
        timestamp AS realtime_timestamp
    FROM
        realtime_flights
    WHERE
        (is_delayed = true OR is_cancelled = true)
        AND timestamp >= CURRENT_TIMESTAMP - INTERVAL '7' DAY
),

realtime_weather_impact AS (
    -- Join real-time weather with delays
    SELECT
        r.origin_airport,
        r.carrier_code,
        r.flight_date,
        r.is_delayed,
        r.arrival_delay_minutes,
        r.delay_reason,
        -- Weather severity calculation (matching Gold layer logic)
        CASE 
            WHEN w.precip_hrly > 0.5 THEN 8
            WHEN w.precip_hrly > 0.1 THEN 5
            WHEN w.snow_hrly > 0 THEN 9
            WHEN w.wspd > 30 THEN 7
            WHEN w.wspd > 20 THEN 4
            WHEN w.vis < 1.0 THEN 8
            WHEN w.vis < 3.0 THEN 5
            WHEN w.temp < 32 OR w.temp > 95 THEN 3
            ELSE 1
        END AS weather_severity_score,
        CASE 
            WHEN w.precip_hrly > 0.5 OR w.snow_hrly > 0 OR w.wspd > 30 OR w.vis < 1.0 THEN 'severe'
            WHEN w.precip_hrly > 0.1 OR w.wspd > 20 OR w.vis < 3.0 THEN 'moderate'
            WHEN w.temp < 32 OR w.temp > 95 THEN 'mild'
            ELSE 'normal'
        END AS weather_impact_category,
        w.wx_phrase,
        w.temp,
        w.precip_hrly,
        w.wspd,
        w.vis
    FROM
        realtime_delays r
    LEFT JOIN
        realtime_weather w
        ON SUBSTRING(w.obs_id, 2, 3) = r.origin_airport  -- Extract IATA from ICAO (KXXX -> XXX)
        AND DATE(FROM_UNIXTIME(w.valid_time_gmt)) = DATE(r.flight_date)
),

delay_composition AS (
    -- Aggregate delay composition
    SELECT
        r.origin_airport,
        r.carrier_code,
        DATE(r.flight_date) AS delay_date,
        EXTRACT(HOUR FROM CAST(r.realtime_timestamp AS TIMESTAMP)) AS delay_hour,
        COUNT(*) AS total_delayed_flights,
        SUM(CASE WHEN r.is_cancelled THEN 1 ELSE 0 END) AS cancelled_flights,
        -- Weather-related delays
        SUM(CASE 
            WHEN w.weather_impact_category IN ('severe', 'moderate') AND r.is_delayed THEN 1 
            ELSE 0 
        END) AS weather_delayed,
        -- Cascade-related delays
        SUM(CASE 
            WHEN r.delay_reason LIKE '%cascade%' OR r.delay_reason LIKE '%rotation%' THEN 1 
            ELSE 0 
        END) AS cascade_delayed,
        -- Operational delays (not weather, not cascade)
        SUM(CASE 
            WHEN r.is_delayed 
                AND w.weather_impact_category NOT IN ('severe', 'moderate')
                AND (r.delay_reason NOT LIKE '%cascade%' AND r.delay_reason NOT LIKE '%rotation%')
            THEN 1 
            ELSE 0 
        END) AS operational_delayed,
        -- Average delays
        ROUND(AVG(r.arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(AVG(r.departure_delay_minutes), 2) AS avg_departure_delay,
        -- Delay reasons breakdown
        COUNT(DISTINCT r.delay_reason) AS unique_delay_reasons
    FROM
        realtime_delays r
    LEFT JOIN
        realtime_weather_impact w
        ON r.origin_airport = w.origin_airport
        AND r.flight_date = w.flight_date
    GROUP BY
        r.origin_airport, r.carrier_code, DATE(r.flight_date),
        EXTRACT(HOUR FROM CAST(r.realtime_timestamp AS TIMESTAMP))
),

historical_root_cause AS (
    -- Historical root cause patterns from Gold layer
    SELECT
        Origin AS origin_airport,
        UniqueCarrier AS carrier_code,
        Year,
        Month,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN ArrDelay > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        SUM(CASE WHEN cascade_occurred = 1 THEN 1 ELSE 0 END) AS cascade_delayed,
        SUM(CASE WHEN buffer_adequacy_category = 'insufficient' THEN 1 ELSE 0 END) AS buffer_issue_delayed,
        ROUND(AVG(ArrDelay), 2) AS avg_arrival_delay,
        ROUND(100.0 * SUM(CASE WHEN ArrDelay > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct
    FROM
        flight_features
    WHERE
        Year >= 2005
    GROUP BY
        Origin, UniqueCarrier, Year, Month
    HAVING
        COUNT(*) >= 100
)

-- Main Result: Root Cause Dashboard
SELECT
    COALESCE(d.origin_airport, h.origin_airport) AS airport,
    COALESCE(d.carrier_code, h.carrier_code) AS carrier,
    d.delay_date,
    d.delay_hour,
    -- Real-time metrics
    d.total_delayed_flights,
    d.cancelled_flights,
    ROUND(100.0 * d.cancelled_flights / NULLIF(d.total_delayed_flights, 0), 2) AS cancellation_rate_pct,
    -- Delay breakdown
    d.weather_delayed,
    ROUND(100.0 * d.weather_delayed / NULLIF(d.total_delayed_flights, 0), 2) AS weather_delay_pct,
    d.cascade_delayed,
    ROUND(100.0 * d.cascade_delayed / NULLIF(d.total_delayed_flights, 0), 2) AS cascade_delay_pct,
    d.operational_delayed,
    ROUND(100.0 * d.operational_delayed / NULLIF(d.total_delayed_flights, 0), 2) AS operational_delay_pct,
    -- Averages
    d.avg_arrival_delay,
    d.avg_departure_delay,
    -- Historical context
    h.delay_rate_pct AS historical_delay_rate_pct,
    h.avg_arrival_delay AS historical_avg_delay,
    -- Primary root cause
    CASE
        WHEN d.cascade_delayed > 0 AND (100.0 * d.cascade_delayed / NULLIF(d.total_delayed_flights, 0)) > 40 THEN 'Cascade Issues'
        WHEN d.weather_delayed > 0 AND (100.0 * d.weather_delayed / NULLIF(d.total_delayed_flights, 0)) > 30 THEN 'Weather'
        WHEN d.operational_delayed > 0 AND (100.0 * d.operational_delayed / NULLIF(d.total_delayed_flights, 0)) > 25 THEN 'Operational'
        WHEN d.cancelled_flights > 0 AND (100.0 * d.cancelled_flights / NULLIF(d.total_delayed_flights, 0)) > 20 THEN 'Cancellations'
        ELSE 'Mixed Causes'
    END AS primary_root_cause,
    -- Trend indicator
    CASE
        WHEN d.avg_arrival_delay > h.avg_arrival_delay * 1.2 THEN 'WORSENING'
        WHEN d.avg_arrival_delay < h.avg_arrival_delay * 0.8 THEN 'IMPROVING'
        ELSE 'STABLE'
    END AS trend
FROM
    delay_composition d
FULL OUTER JOIN
    historical_root_cause h
    ON d.origin_airport = h.origin_airport
    AND d.carrier_code = h.carrier_code
WHERE
    d.total_delayed_flights >= 5  -- Minimum sample size
    OR h.total_flights >= 100
ORDER BY
    d.delay_date DESC,
    d.delay_hour DESC,
    d.total_delayed_flights DESC
LIMIT 1000;

