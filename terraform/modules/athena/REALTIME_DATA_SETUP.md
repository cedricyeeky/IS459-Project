# Real-Time Data Setup for Athena Queries

## Overview

The Athena queries integrate real-time data from your API with historical Gold layer data. This document explains how to set up the real-time data tables in AWS Glue Data Catalog.

## Required Tables

### 1. `realtime_flights` Table

This table should contain flight data from your API with the following schema:

```sql
CREATE EXTERNAL TABLE realtime_flights (
    flight_id STRING,
    carrier_code STRING,
    carrier_name STRING,
    origin_airport STRING,
    destination_airport STRING,
    origin_city STRING,
    destination_city STRING,
    flight_date STRING,  -- Format: 'YYYY-MM-DD'
    flight_number STRING,
    tail_number STRING,
    hour_of_day INT,
    day_of_week STRING,
    is_weekend BOOLEAN,
    scheduled_departure STRING,  -- ISO timestamp
    scheduled_arrival STRING,   -- ISO timestamp
    actual_departure STRING,     -- ISO timestamp (nullable)
    actual_arrival STRING,       -- ISO timestamp (nullable)
    arrival_delay_minutes INT,
    departure_delay_minutes INT,
    is_delayed BOOLEAN,
    is_cancelled BOOLEAN,
    on_time BOOLEAN,
    status STRING,  -- 'SCHEDULED', 'BOARDING', 'DEPARTED', 'IN_AIR', 'LANDED', 'ARRIVED', 'DELAYED', 'CANCELLED'
    delay_reason STRING,  -- nullable
    cascade_risk BOOLEAN,
    carrier_reliability_score DOUBLE,
    reliability_band STRING,  -- 'EXCELLENT', 'HIGH', 'MEDIUM', 'LOW', 'POOR'
    origin_traffic_level STRING,  -- 'low', 'medium', 'high'
    destination_traffic_level STRING,  -- 'low', 'medium', 'high'
    aircraft_type STRING,
    timestamp STRING  -- ISO timestamp of when record was created
)
STORED AS PARQUET
LOCATION 's3://your-bucket/realtime/flights/'
TBLPROPERTIES (
    'projection.enabled' = 'true',
    'projection.timestamp.type' = 'date',
    'projection.timestamp.format' = 'yyyy-MM-dd',
    'projection.timestamp.range' = '2024-01-01,NOW',
    'storage.location.template' = 's3://your-bucket/realtime/flights/${timestamp}/'
);
```

### 2. `realtime_weather` Table

This table should contain weather data matching your `weather_data_list*.csv` format:

```sql
CREATE EXTERNAL TABLE realtime_weather (
    obs_id STRING,  -- ICAO code (e.g., 'KORD', 'KJFK')
    valid_time_gmt BIGINT,  -- Unix timestamp
    wx_phrase STRING,  -- Weather condition description
    temp DOUBLE,
    precip_hrly DOUBLE,  -- nullable
    snow_hrly DOUBLE,    -- nullable
    wspd DOUBLE,         -- Wind speed
    clds STRING,         -- Cloud cover code
    rh DOUBLE,           -- Relative humidity
    vis DOUBLE           -- Visibility
)
STORED AS PARQUET
LOCATION 's3://your-bucket/realtime/weather/'
TBLPROPERTIES (
    'projection.enabled' = 'true',
    'projection.valid_time_gmt.type' = 'date',
    'projection.valid_time_gmt.format' = 'yyyy-MM-dd',
    'projection.valid_time_gmt.range' = '2024-01-01,NOW',
    'storage.location.template' = 's3://your-bucket/realtime/weather/${valid_time_gmt}/'
);
```

## Setup Instructions

### Option 1: Using AWS Glue Crawler (Recommended)

1. **Create S3 Bucket Structure**:
   ```
   s3://your-bucket/
   ├── realtime/
   │   ├── flights/
   │   │   └── YYYY-MM-DD/
   │   │       └── data.parquet
   │   └── weather/
   │       └── YYYY-MM-DD/
   │           └── data.parquet
   ```

2. **Create Glue Crawler**:
   ```bash
   aws glue create-crawler \
     --name realtime-flights-crawler \
     --role arn:aws:iam::ACCOUNT:role/GlueServiceRole \
     --database-name flight_delays_db \
     --targets '{"S3Targets": [{"Path": "s3://your-bucket/realtime/flights/"}]}'
   ```

3. **Run Crawler**:
   ```bash
   aws glue start-crawler --name realtime-flights-crawler
   ```

### Option 2: Manual Table Creation

Use the `CREATE EXTERNAL TABLE` statements above in Athena Query Editor.

## Data Ingestion from API

Your API should write data in the following format:

### Flight Data JSON Example:
```json
{
  "flight_id": "US8286_20251110_LAS_DFW",
  "carrier_code": "US",
  "carrier_name": "US Airways Inc.",
  "origin_airport": "LAS",
  "destination_airport": "DFW",
  "flight_date": "2025-11-10",
  "scheduled_departure": "2025-11-10T17:00:00",
  "actual_arrival": "2025-11-10T19:47:54.843687",
  "arrival_delay_minutes": 0,
  "is_delayed": false,
  "cascade_risk": false,
  "carrier_reliability_score": 0.8,
  "reliability_band": "EXCELLENT",
  "timestamp": "2025-11-10T16:46:22.511113"
}
```

### Weather Data CSV Format:
```csv
obs_id,valid_time_gmt,wx_phrase,temp,precip_hrly,snow_hrly,wspd,clds,rh,vis
KORD,560062800,Fair,44.0,,,5.0,CLR,79.0,15.0
```

## Query Usage

All queries are available as named queries in Athena. You can:

1. **Access via Athena Console**:
   - Go to Athena Query Editor
   - Click "Saved queries" tab
   - Select query by name (e.g., `flight-delays-dev-cascade-probability-matrix`)

2. **Access via AWS CLI**:
   ```bash
   aws athena get-named-query --named-query-id <query-id>
   ```

3. **Access via Terraform Outputs**:
   ```bash
   terraform output athena_named_queries
   ```

## Data Refresh Strategy

- **Real-time Flight Data**: Update every 1-5 minutes
- **Real-time Weather Data**: Update every 15-30 minutes
- **Historical Gold Layer**: Updated via Glue ETL jobs (weekly/monthly)

## Notes

- All queries use `FULL OUTER JOIN` to combine real-time and historical data
- Queries handle missing real-time data gracefully (fallback to historical)
- Weather data uses `SUBSTRING(obs_id, 2, 3)` to extract IATA codes from ICAO (KXXX → XXX)
- Timestamps are converted using `FROM_UNIXTIME()` for weather data
- Date comparisons use `DATE()` function for consistency

## Troubleshooting

1. **Table Not Found**: Ensure tables are created in the same database as Gold layer tables
2. **No Data**: Check S3 bucket paths and partition structure
3. **Join Failures**: Verify airport codes match between real-time and historical data (IATA format)
4. **Performance**: Ensure tables are partitioned by date for optimal query performance

