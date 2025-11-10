-- ============================================================================
-- Query 3: WHY do delays begin?
-- ============================================================================
-- Analyzes root causes: weather correlation, holiday impact, operational factors
-- This query answers: "WHY do delays occur at certain times/places?"

-- Weather Impact Analysis
WITH weather_impact AS (
    SELECT
        weather_severity_score,
        temp_category,
        precip_category,
        visibility_category,
        wind_category,
        weather_delay_likelihood,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN ArrDelay > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN ArrDelay > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(ArrDelay), 2) AS avg_delay_minutes,
        ROUND(APPROX_PERCENTILE(ArrDelay, 0.90), 2) AS p90_delay_minutes
    FROM
        flight_features
    WHERE
        Year >= 2005
        AND Cancelled = 0
        AND weather_severity_score IS NOT NULL
    GROUP BY
        weather_severity_score, temp_category, precip_category, 
        visibility_category, wind_category, weather_delay_likelihood
),

-- Holiday Impact Analysis
holiday_impact AS (
    SELECT
        holiday_proximity_category,
        is_weekend,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN ArrDelay > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN ArrDelay > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(ArrDelay), 2) AS avg_delay_minutes
    FROM
        flight_features
    WHERE
        Year >= 2005
        AND Cancelled = 0
        AND holiday_proximity_category IS NOT NULL
    GROUP BY
        holiday_proximity_category, is_weekend
),

-- Weather × Holiday Interaction
interaction_analysis AS (
    SELECT
        holiday_proximity_category,
        weather_delay_likelihood,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN ArrDelay > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN ArrDelay > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(ArrDelay), 2) AS avg_delay_minutes
    FROM
        flight_features
    WHERE
        Year >= 2005
        AND Cancelled = 0
        AND holiday_proximity_category IS NOT NULL
        AND weather_delay_likelihood IS NOT NULL
    GROUP BY
        holiday_proximity_category, weather_delay_likelihood
    HAVING
        COUNT(*) >= 100
),

-- Carrier Performance by Conditions
carrier_weather_performance AS (
    SELECT
        UniqueCarrier AS carrier,
        weather_delay_likelihood,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN ArrDelay > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN ArrDelay > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(ArrDelay), 2) AS avg_delay_minutes
    FROM
        flight_features
    WHERE
        Year >= 2005
        AND Cancelled = 0
        AND weather_delay_likelihood IN ('high', 'very_high')
    GROUP BY
        UniqueCarrier, weather_delay_likelihood
    HAVING
        COUNT(*) >= 500
)

-- Main Result: Weather Severity Correlation
SELECT
    'Weather Impact' AS analysis_type,
    weather_severity_score,
    weather_delay_likelihood,
    temp_category,
    precip_category,
    visibility_category,
    wind_category,
    total_flights,
    delayed_flights,
    delay_rate_pct,
    avg_delay_minutes,
    p90_delay_minutes,
    ROUND(delay_rate_pct / NULLIF((SELECT AVG(delay_rate_pct) FROM weather_impact), 0), 2) AS delay_rate_multiplier
FROM
    weather_impact
WHERE
    total_flights >= 1000  -- Statistical significance
ORDER BY
    weather_severity_score DESC,
    delay_rate_pct DESC
LIMIT 100;
