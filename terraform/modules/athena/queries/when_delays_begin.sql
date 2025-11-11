-- ============================================================================
-- Query 1: WHEN do delays begin?
-- ============================================================================
-- Analyzes temporal patterns: peak delay hours, seasonal trends, holiday impact
-- This query answers: "WHEN are delays most likely to occur?"

-- Peak Delay Hours by Airport and Time of Day
WITH hourly_delays AS (
    SELECT
        Origin AS airport,
        hour_category,
        flight_hour,
        season,
        is_weekend,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(TRY_CAST(arrdelay AS DOUBLE)), 2) AS avg_delay_minutes,
        ROUND(APPROX_PERCENTILE(TRY_CAST(arrdelay AS DOUBLE), 0.90), 2) AS p90_delay_minutes,
        ROUND(APPROX_PERCENTILE(TRY_CAST(arrdelay AS DOUBLE), 0.50), 2) AS median_delay_minutes
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 1987  -- Use all available data
        AND cancelled = 0
        AND flight_hour IS NOT NULL
    GROUP BY
        Origin, hour_category, flight_hour, season, is_weekend
    HAVING
        COUNT(*) >= 5  -- Lowered threshold for more results
),

-- Seasonal Patterns
seasonal_analysis AS (
    SELECT
        season,
        hour_category,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(TRY_CAST(arrdelay AS DOUBLE)), 2) AS avg_delay_minutes
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 1987  -- Use all available data
        AND cancelled = 0
    GROUP BY
        season, hour_category
),

-- Weekend vs Weekday Analysis
day_type_analysis AS (
    SELECT
        CASE WHEN is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
        hour_category,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(TRY_CAST(arrdelay AS DOUBLE)), 2) AS avg_delay_minutes
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 1987  -- Use all available data
        AND cancelled = 0
    GROUP BY
        is_weekend, hour_category
)

-- Main Result: Top Delay Hours by Airport
SELECT
    'Hourly Pattern' AS analysis_type,
    airport,
    hour_category,
    flight_hour,
    season,
    CASE WHEN is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    total_flights,
    delayed_flights,
    delay_rate_pct,
    avg_delay_minutes,
    p90_delay_minutes,
    median_delay_minutes
FROM
    hourly_delays
ORDER BY
    delay_rate_pct DESC,
    avg_delay_minutes DESC
LIMIT 100;
