-- ============================================================================
-- Query 2: WHERE do delays begin?
-- ============================================================================
-- Analyzes geographic hotspots: worst airports, routes, hub performance
-- This query answers: "WHERE are delays most concentrated?"




-- Airport Performance Rankings
WITH airport_rankings AS (
    SELECT
        Origin AS airport,
        airport_type,
        origin_region AS region,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(TRY_CAST(arrdelay AS DOUBLE)), 2) AS avg_delay_minutes,
        ROUND(APPROX_PERCENTILE(TRY_CAST(arrdelay AS DOUBLE), 0.90), 2) AS p90_delay_minutes,
        ROUND(AVG(TRY_CAST(buffer_shortfall_minutes AS DOUBLE)), 2) AS avg_buffer_shortfall,
        SUM(CASE WHEN buffer_adequacy_category = 'insufficient' THEN 1 ELSE 0 END) AS insufficient_buffer_count
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 1987  -- Use all available data
        AND cancelled = 0
    GROUP BY
        Origin, airport_type, origin_region
    HAVING
        COUNT(*) >= 100  -- Lowered threshold for more results
),

-- Route Hotspots (Origin-Destination pairs)
route_hotspots AS (
    SELECT
        Origin AS origin_airport,
        Dest AS dest_airport,
        route_type,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(TRY_CAST(arrdelay AS DOUBLE)), 2) AS avg_delay_minutes,
        ROUND(AVG(TRY_CAST(buffer_shortfall_minutes AS DOUBLE)), 2) AS avg_buffer_shortfall
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 1987  -- Use all available data
        AND cancelled = 0
    GROUP BY
        Origin, Dest, route_type
    HAVING
        COUNT(*) >= 20  -- Lowered threshold for more routes
),

-- Hub Performance Comparison
hub_comparison AS (
    SELECT
        Origin AS hub_airport,
        airport_type,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) AS delayed_flights,
        ROUND(100.0 * SUM(CASE WHEN TRY_CAST(arrdelay AS DOUBLE) > 15 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS delay_rate_pct,
        ROUND(AVG(TRY_CAST(arrdelay AS DOUBLE)), 2) AS avg_delay_minutes,
        COUNT(DISTINCT Dest) AS destinations_served,
        COUNT(DISTINCT UniqueCarrier) AS carriers_operating
    FROM
        "flight-delays-dev-db".flight_features
    WHERE
        CAST(year AS INT) >= 1987  -- Use all available data
        AND cancelled = 0
        AND airport_type IN ('major_hub', 'international_gateway')
    GROUP BY
        Origin, airport_type
)

-- Main Result: Worst Performing Airports
SELECT
    'Airport Hotspots' AS analysis_type,
    airport,
    airport_type,
    region,
    total_flights,
    delayed_flights,
    delay_rate_pct,
    avg_delay_minutes,
    p90_delay_minutes,
    avg_buffer_shortfall,
    insufficient_buffer_count,
    ROUND(100.0 * insufficient_buffer_count / NULLIF(total_flights, 0), 2) AS insufficient_buffer_pct
FROM
    airport_rankings
WHERE
    delay_rate_pct > 15  -- Lowered threshold to include more airports
ORDER BY
    delay_rate_pct DESC,
    total_flights DESC
LIMIT 50;
