-- SEASONAL RISK ASSESSMENT
-- Rewritten to use actual available schema from flights table
-- Original purpose: Seasonal risk patterns and weather-based delay assessment
-- Simplified: Derives season from flight_date, uses cascade_risk and delay patterns

WITH seasonal_flights AS (
    SELECT
        origin_airport,
        destination_airport,
        carrier,
        flight_date,
        month,
        day_of_week,
        hour_of_day,
        arrival_delay_minutes,
        departure_delay_minutes,
        is_cancelled,
        is_diverted,
        cascade_risk,
        CASE WHEN arrival_delay_minutes <= 15 THEN 1 ELSE 0 END AS on_time_flag,
        CASE WHEN arrival_delay_minutes > 15 THEN 1 ELSE 0 END AS delayed_flag,
        -- Derive season from month
        CASE
            WHEN month IN (12, 1, 2) THEN 'Winter'
            WHEN month IN (3, 4, 5) THEN 'Spring'
            WHEN month IN (6, 7, 8) THEN 'Summer'
            WHEN month IN (9, 10, 11) THEN 'Fall'
        END AS season,
        -- Weekend flag
        CASE WHEN day_of_week IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END AS is_weekend
    FROM "flight-delays-dev-db".flights
    WHERE FROM_ISO8601_TIMESTAMP(timestamp) >= CURRENT_TIMESTAMP - INTERVAL '90' DAY
),

seasonal_performance AS (
    SELECT
        season,
        origin_airport,
        destination_airport,
        COUNT(*) AS total_flights,
        SUM(on_time_flag) AS on_time_count,
        SUM(delayed_flag) AS delayed_count,
        SUM(CASE WHEN is_cancelled = true THEN 1 ELSE 0 END) AS cancelled_count,
        SUM(CASE WHEN cascade_risk = true THEN 1 ELSE 0 END) AS cascade_events,
        ROUND(100.0 * SUM(on_time_flag) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(delayed_flag) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(100.0 * SUM(CASE WHEN is_cancelled = true THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
        ROUND(100.0 * SUM(CASE WHEN cascade_risk = true THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cascade_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(AVG(departure_delay_minutes), 2) AS avg_departure_delay,
        ROUND(MAX(arrival_delay_minutes), 2) AS max_delay,
        ROUND(STDDEV(arrival_delay_minutes), 2) AS stddev_arrival_delay
    FROM seasonal_flights
    GROUP BY season, origin_airport, destination_airport
    HAVING COUNT(*) >= 10  -- Require minimum sample
),

weekend_vs_weekday AS (
    SELECT
        season,
        is_weekend,
        COUNT(*) AS total_flights,
        ROUND(100.0 * SUM(on_time_flag) / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(delayed_flag) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_delay
    FROM seasonal_flights
    GROUP BY season, is_weekend
),

carrier_seasonal_performance AS (
    SELECT
        season,
        carrier,
        COUNT(*) AS total_flights,
        ROUND(100.0 * SUM(on_time_flag) / NULLIF(COUNT(*), 0), 2) AS carrier_on_time_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS carrier_avg_delay
    FROM seasonal_flights
    GROUP BY season, carrier
    HAVING COUNT(*) >= 5
)

-- FINAL OUTPUT: Seasonal risk assessment with rankings
SELECT
    sp.season,
    sp.origin_airport,
    sp.destination_airport,
    sp.total_flights,
    sp.on_time_rate_pct,
    sp.delay_rate_pct,
    sp.cancellation_rate_pct,
    sp.cascade_rate_pct,
    sp.avg_arrival_delay,
    sp.avg_departure_delay,
    sp.max_delay,
    sp.stddev_arrival_delay,
    wvw_weekday.on_time_rate_pct AS weekday_on_time_rate,
    wvw_weekend.on_time_rate_pct AS weekend_on_time_rate,
    csp.carrier_on_time_rate_pct AS carrier_avg_on_time_rate,
    -- Risk score: combine delay rate, cancellation rate, cascade rate, and variability
    ROUND((sp.delay_rate_pct + sp.cancellation_rate_pct * 2 + sp.cascade_rate_pct * 1.5 + COALESCE(sp.stddev_arrival_delay, 0) / 10), 2) AS seasonal_risk_score,
    CASE
        WHEN sp.delay_rate_pct >= 40 OR sp.cascade_rate_pct >= 30 THEN 'HIGH_RISK'
        WHEN sp.delay_rate_pct >= 25 OR sp.cascade_rate_pct >= 15 THEN 'MEDIUM_RISK'
        ELSE 'LOW_RISK'
    END AS risk_category
FROM seasonal_performance sp
LEFT JOIN weekend_vs_weekday wvw_weekday 
    ON sp.season = wvw_weekday.season 
    AND wvw_weekday.is_weekend = 0
LEFT JOIN weekend_vs_weekday wvw_weekend 
    ON sp.season = wvw_weekend.season 
    AND wvw_weekend.is_weekend = 1
LEFT JOIN carrier_seasonal_performance csp 
    ON sp.season = csp.season
ORDER BY sp.season, seasonal_risk_score DESC
LIMIT 100;
