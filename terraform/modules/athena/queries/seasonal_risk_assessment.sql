-- ============================================================================
-- BQ2: Seasonal Risk Assessment with Weather Impact Guidance
-- ============================================================================
-- Combines real-time flight data, weather data, and historical Gold layer
-- Output: Seasonal risk assessments and weather impact guidance

WITH realtime_seasonal_analysis AS (
    -- Real-time seasonal performance from mock API
    SELECT
        origin_airport,
        destination_airport,
        -- Derive season from flight_date
        CASE
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (12, 1, 2) THEN 'winter'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (3, 4, 5) THEN 'spring'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (6, 7, 8) THEN 'summer'
            ELSE 'fall'
        END AS season,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN on_time THEN 1 ELSE 0 END) AS on_time_flights,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS cancelled_flights,
        ROUND(100.0 * SUM(CASE WHEN on_time THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(APPROX_PERCENTILE(arrival_delay_minutes, 0.9), 2) AS p90_arrival_delay
    FROM
        realtime_flights
    WHERE
        timestamp >= CURRENT_TIMESTAMP - INTERVAL '90' DAY
    GROUP BY
        origin_airport, destination_airport,
        CASE
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (12, 1, 2) THEN 'winter'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (3, 4, 5) THEN 'spring'
            WHEN EXTRACT(MONTH FROM CAST(flight_date AS DATE)) IN (6, 7, 8) THEN 'summer'
            ELSE 'fall'
        END
    HAVING
        COUNT(*) >= 10
),

realtime_weather_impact AS (
    -- Real-time weather impact analysis
    SELECT
        r.origin_airport,
        r.destination_airport,
        r.season,
        -- Weather severity calculation
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
        COUNT(*) AS weather_affected_flights,
        SUM(CASE WHEN r.is_delayed THEN 1 ELSE 0 END) AS weather_delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN r.is_delayed THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS weather_impact_pct
    FROM
        realtime_flights r
    JOIN
        realtime_weather w
        ON SUBSTRING(w.obs_id, 2, 3) = r.origin_airport
        AND DATE(FROM_UNIXTIME(w.valid_time_gmt)) = DATE(r.flight_date)
    WHERE
        r.timestamp >= CURRENT_TIMESTAMP - INTERVAL '90' DAY
    GROUP BY
        r.origin_airport, r.destination_airport,
        CASE
            WHEN EXTRACT(MONTH FROM CAST(r.flight_date AS DATE)) IN (12, 1, 2) THEN 'winter'
            WHEN EXTRACT(MONTH FROM CAST(r.flight_date AS DATE)) IN (3, 4, 5) THEN 'spring'
            WHEN EXTRACT(MONTH FROM CAST(r.flight_date AS DATE)) IN (6, 7, 8) THEN 'summer'
            ELSE 'fall'
        END,
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
        END,
        CASE 
            WHEN w.precip_hrly > 0.5 OR w.snow_hrly > 0 OR w.wspd > 30 OR w.vis < 1.0 THEN 'severe'
            WHEN w.precip_hrly > 0.1 OR w.wspd > 20 OR w.vis < 3.0 THEN 'moderate'
            WHEN w.temp < 32 OR w.temp > 95 THEN 'mild'
            ELSE 'normal'
        END
),

historical_seasonal_analysis AS (
    -- Historical seasonal performance from Gold layer
    SELECT
        Origin AS origin_airport,
        Dest AS destination_airport,
        season,
        COUNT(*) AS total_flights,
        SUM(on_time_flag) AS on_time_flights,
        SUM(cancelled_flag) AS cancelled_flights,
        ROUND(100.0 * SUM(on_time_flag) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(cancelled_flag) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(AVG(ArrDelay), 2) AS avg_arrival_delay,
        ROUND(PERCENTILE_APPROX(ArrDelay, 0.9, 100), 2) AS p90_arrival_delay
    FROM
        flight_features
    WHERE
        Year >= 2005
    GROUP BY
        Origin, Dest, season
    HAVING
        COUNT(*) >= 30
)

-- Main Result: Seasonal Risk Assessment
SELECT
    COALESCE(r.origin_airport, h.origin_airport) AS origin_airport,
    COALESCE(r.destination_airport, h.destination_airport) AS destination_airport,
    COALESCE(r.season, h.season) AS season,
    -- Real-time metrics
    r.total_flights AS realtime_flight_count,
    r.on_time_rate_pct AS realtime_on_time_rate_pct,
    r.cancellation_rate_pct AS realtime_cancellation_rate_pct,
    r.avg_arrival_delay AS realtime_avg_delay,
    r.p90_arrival_delay AS realtime_p90_delay,
    -- Historical metrics
    h.total_flights AS historical_flight_count,
    h.on_time_rate_pct AS historical_on_time_rate_pct,
    h.cancellation_rate_pct AS historical_cancellation_rate_pct,
    h.avg_arrival_delay AS historical_avg_delay,
    h.p90_arrival_delay AS historical_p90_delay,
    -- Weather impact
    w.weather_impact_pct,
    w.weather_impact_category,
    w.weather_affected_flights,
    -- Combined risk level
    CASE
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) < 60 
             OR COALESCE(r.cancellation_rate_pct, h.cancellation_rate_pct) > 10 THEN 'HIGH_RISK'
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) < 70 
             OR COALESCE(r.cancellation_rate_pct, h.cancellation_rate_pct) > 5 THEN 'MEDIUM_RISK'
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) < 80 THEN 'LOW_RISK'
        ELSE 'LOW_RISK'
    END AS risk_level,
    -- Seasonal guidance
    CASE
        WHEN r.season = 'winter' AND w.weather_impact_pct > 20 THEN 'HIGH weather risk - Consider travel insurance'
        WHEN r.season = 'summer' AND w.weather_impact_pct > 15 THEN 'MODERATE weather risk - Monitor forecasts'
        WHEN r.season IN ('spring', 'fall') AND COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) < 75 THEN 'MODERATE risk - Book flexible tickets'
        WHEN COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) >= 80 THEN 'LOW risk - Standard booking OK'
        ELSE 'MODERATE risk - Review cancellation policies'
    END AS travel_guidance,
    -- Best season ranking for this route
    ROW_NUMBER() OVER (
        PARTITION BY 
            COALESCE(r.origin_airport, h.origin_airport),
            COALESCE(r.destination_airport, h.destination_airport)
        ORDER BY 
            COALESCE(r.on_time_rate_pct, h.on_time_rate_pct) DESC,
            COALESCE(r.cancellation_rate_pct, h.cancellation_rate_pct) ASC
    ) AS season_rank
FROM
    realtime_seasonal_analysis r
FULL OUTER JOIN
    historical_seasonal_analysis h
    ON r.origin_airport = h.origin_airport
    AND r.destination_airport = h.destination_airport
    AND r.season = h.season
LEFT JOIN
    realtime_weather_impact w
    ON r.origin_airport = w.origin_airport
    AND r.destination_airport = w.destination_airport
    AND r.season = w.season
ORDER BY
    origin_airport, destination_airport, season_rank;

