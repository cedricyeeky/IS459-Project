-- ============================================================================
-- Create Clean Views for Real-Time Data
-- ============================================================================
-- Purpose: Provide clean, consistent aliases for crawler-generated tables
-- Crawlers create tables with partition-based names (e.g., scraped_flights_*)
-- These views provide predictable names for hybrid queries
--
-- Usage:
--   1. Find actual table names: SHOW TABLES IN flight_delays_dev_db;
--   2. Update table references below with actual names
--   3. Run in Athena query editor or via AWS CLI
--
-- Run with:
--   aws athena start-query-execution \
--     --query-string "$(cat create_realtime_views.sql)" \
--     --query-execution-context Database=flight-delays-dev-db \
--     --result-configuration OutputLocation=s3://flight-delays-dev-athena-results/ \
--     --profile flight-delays
-- ============================================================================

-- ============================================================================
-- View: realtime_flights
-- ============================================================================
-- Provides clean interface to scraped flight data from Lambda/EventBridge
-- Maps to Glue table created by realtime-flights-crawler

-- ⚠️ IMPORTANT: Replace 'scraped_flights' with actual table name from crawler
-- Find with: SHOW TABLES LIKE '*flight*';

CREATE OR REPLACE VIEW realtime_flights AS
SELECT
    -- Identifiers
    flight_id,
    flight_number,
    tail_number,
    carrier_code,
    carrier_name,
    
    -- Airports
    origin_airport,
    destination_airport,
    origin_city,
    destination_city,
    origin_traffic_level,
    destination_traffic_level,
    
    -- Temporal
    flight_date,
    hour_of_day,
    day_of_week,
    is_weekend,
    
    -- Scheduled times (ISO 8601 format)
    scheduled_departure,
    scheduled_arrival,
    
    -- Actual times (nullable)
    actual_departure,
    actual_arrival,
    
    -- Delays
    arrival_delay_minutes,
    departure_delay_minutes,
    is_delayed,
    delay_reason,
    
    -- Status
    status,                         -- SCHEDULED/DEPARTED/ARRIVED/DELAYED/CANCELLED
    is_cancelled,
    on_time,
    
    -- BQ1 Features (Cascade Analysis)
    cascade_risk,                   -- Boolean: High risk of causing downstream delays
    
    -- BQ2 Features (Reliability Scoring)
    carrier_reliability_score,      -- 0.0-1.0 score
    reliability_band,               -- EXCELLENT/HIGH/MEDIUM/LOW/POOR
    
    -- Aircraft
    aircraft_type,
    
    -- Metadata
    timestamp AS scrape_timestamp,
    api_version,
    data_source
FROM
    scraped_flights  -- ⚠️ Replace with actual crawler-generated table name
;

-- Verify view created
SELECT COUNT(*) as total_flights, 
       MIN(flight_date) as earliest_date,
       MAX(flight_date) as latest_date
FROM realtime_flights;


-- ============================================================================
-- View: realtime_weather
-- ============================================================================
-- Provides clean interface to scraped weather data from Lambda/EventBridge
-- Maps to Glue table created by realtime-weather-crawler

-- ⚠️ IMPORTANT: Replace 'scraped_weather' with actual table name from crawler
-- Find with: SHOW TABLES LIKE '*weather*';

CREATE OR REPLACE VIEW realtime_weather AS
SELECT
    -- Identifiers
    obs_id,                         -- Format: AIRPORT_YYYYMMDDHHMI
    airport_code,                   -- IATA code (ORD, ATL, DFW, etc.)
    airport_city,
    
    -- Temporal
    observation_time,               -- ISO 8601 timestamp
    valid_time_gmt,                 -- Unix timestamp
    
    -- Temperature
    temp,                           -- Fahrenheit
    
    -- Precipitation
    precip_hrly,                    -- Inches per hour
    snow_hrly,                      -- Inches per hour
    
    -- Wind
    wspd,                           -- Wind speed (mph)
    
    -- Visibility
    vis,                            -- Visibility (miles)
    
    -- Humidity & Clouds
    rh,                             -- Relative humidity (%)
    clds,                           -- Cloud cover (CLR/FEW/SCT/BKN/OVC)
    
    -- Description
    wx_phrase,                      -- Human-readable weather phrase
    
    -- Metadata
    timestamp AS scrape_timestamp,
    api_version,
    data_source
FROM
    scraped_weather  -- ⚠️ Replace with actual crawler-generated table name
;

-- Verify view created
SELECT COUNT(*) as total_observations,
       COUNT(DISTINCT airport_code) as unique_airports,
       MIN(observation_time) as earliest_obs,
       MAX(observation_time) as latest_obs
FROM realtime_weather;


-- ============================================================================
-- Utility Queries: Inspect Real-Time Data
-- ============================================================================

-- Show sample real-time flights
SELECT 
    flight_id,
    carrier_code,
    origin_airport,
    destination_airport,
    scheduled_departure,
    delay_reason,
    cascade_risk
FROM realtime_flights
LIMIT 10;

-- Show sample real-time weather
SELECT
    airport_code,
    observation_time,
    temp,
    precip_hrly,
    wspd,
    vis,
    wx_phrase
FROM realtime_weather
LIMIT 10;

-- Check data freshness (how old is the most recent scrape?)
SELECT
    'Flights' AS data_type,
    MAX(scrape_timestamp) AS latest_scrape,
    CAST(date_diff('second', 
        MAX(CAST(scrape_timestamp AS TIMESTAMP)), 
        current_timestamp) AS INTEGER) / 60 AS minutes_ago
FROM realtime_flights

UNION ALL

SELECT
    'Weather' AS data_type,
    MAX(scrape_timestamp) AS latest_scrape,
    CAST(date_diff('second', 
        MAX(CAST(scrape_timestamp AS TIMESTAMP)), 
        current_timestamp) AS INTEGER) / 60 AS minutes_ago
FROM realtime_weather;

-- Check for delayed flights in real-time
SELECT
    carrier_code,
    COUNT(*) AS delayed_flights,
    AVG(arrival_delay_minutes) AS avg_delay,
    COUNT(CASE WHEN cascade_risk = true THEN 1 END) AS cascade_risk_count
FROM realtime_flights
WHERE is_delayed = true
GROUP BY carrier_code
ORDER BY delayed_flights DESC;

-- Check weather severity distribution
SELECT
    airport_code,
    COUNT(*) AS obs_count,
    AVG(temp) AS avg_temp,
    MAX(precip_hrly) AS max_precip,
    MAX(wspd) AS max_wind,
    MIN(vis) AS min_visibility
FROM realtime_weather
GROUP BY airport_code
ORDER BY max_precip DESC;
