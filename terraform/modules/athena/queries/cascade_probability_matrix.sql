-- CASCADE PROBABILITY MATRIX & HIGH-RISK STATION IDENTIFICATION
-- Rewritten to use actual available schema from flights table
-- Original purpose: Identify cascade probability between stations and high-risk airports
-- Simplified: Uses cascade_risk boolean flag and delay patterns

WITH realtime_cascades AS (
    SELECT
        origin_airport,
        destination_airport,
        tail_number,
        carrier,
        flight_date,
        hour_of_day,
        day_of_week,
        cascade_risk,
        arrival_delay_minutes,
        departure_delay_minutes,
        is_cancelled,
        timestamp
    FROM "flight-delays-dev-db".flights
    WHERE FROM_ISO8601_TIMESTAMP(timestamp) >= CURRENT_TIMESTAMP - INTERVAL '24' HOUR
),

cascade_by_route AS (
    SELECT
        origin_airport,
        destination_airport,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN cascade_risk = true THEN 1 ELSE 0 END) AS cascade_events,
        ROUND(100.0 * SUM(CASE WHEN cascade_risk = true THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cascade_rate_pct,
        ROUND(AVG(arrival_delay_minutes), 2) AS avg_arrival_delay,
        ROUND(AVG(departure_delay_minutes), 2) AS avg_departure_delay,
        SUM(CASE WHEN is_cancelled = true THEN 1 ELSE 0 END) AS cancellations
    FROM realtime_cascades
    GROUP BY origin_airport, destination_airport
    HAVING COUNT(*) >= 5  -- Require minimum sample size
),

origin_risk_scores AS (
    SELECT
        origin_airport,
        COUNT(DISTINCT destination_airport) AS destinations_served,
        SUM(total_flights) AS total_departures,
        SUM(cascade_events) AS total_cascade_triggers,
        ROUND(100.0 * SUM(cascade_events) / NULLIF(SUM(total_flights), 0), 2) AS origin_cascade_rate_pct,
        ROUND(AVG(avg_arrival_delay), 2) AS avg_downstream_delay,
        SUM(cancellations) AS total_cancellations
    FROM cascade_by_route
    GROUP BY origin_airport
),

destination_risk_scores AS (
    SELECT
        destination_airport,
        COUNT(DISTINCT origin_airport) AS origins_served,
        SUM(total_flights) AS total_arrivals,
        SUM(cascade_events) AS total_cascade_impacts,
        ROUND(100.0 * SUM(cascade_events) / NULLIF(SUM(total_flights), 0), 2) AS dest_cascade_rate_pct,
        ROUND(AVG(avg_arrival_delay), 2) AS avg_arrival_delay,
        SUM(cancellations) AS total_cancellations
    FROM cascade_by_route
    GROUP BY destination_airport
)

-- FINAL OUTPUT: Cascade probability matrix with high-risk stations
SELECT
    'CASCADE_MATRIX' AS report_section,
    cbr.origin_airport,
    cbr.destination_airport,
    cbr.total_flights,
    cbr.cascade_events,
    cbr.cascade_rate_pct,
    cbr.avg_arrival_delay,
    cbr.avg_departure_delay,
    cbr.cancellations,
    ors.origin_cascade_rate_pct AS origin_overall_cascade_rate,
    drs.dest_cascade_rate_pct AS dest_overall_cascade_rate,
    CASE
        WHEN cbr.cascade_rate_pct >= 50 THEN 'CRITICAL'
        WHEN cbr.cascade_rate_pct >= 30 THEN 'HIGH'
        WHEN cbr.cascade_rate_pct >= 15 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS route_risk_level,
    CASE
        WHEN ors.origin_cascade_rate_pct >= 40 THEN 'HIGH_RISK_ORIGIN'
        WHEN drs.dest_cascade_rate_pct >= 40 THEN 'HIGH_RISK_DESTINATION'
        ELSE 'NORMAL'
    END AS station_risk_classification
FROM cascade_by_route cbr
LEFT JOIN origin_risk_scores ors ON cbr.origin_airport = ors.origin_airport
LEFT JOIN destination_risk_scores drs ON cbr.destination_airport = drs.destination_airport
ORDER BY cbr.cascade_rate_pct DESC, cbr.total_flights DESC
LIMIT 50;
