"""
Glue Job 2: Feature Engineering
================================
This script reads cleaned data from the Silver bucket, performs feature engineering,
and writes analysis-ready features to the Gold bucket in Parquet format.
Failed records are written to the DLQ bucket with error metadata.
"""

import sys
import json
from datetime import datetime
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import DataFrame, Window
from pyspark.sql.functions import (
    col, when, lit, current_timestamp, avg, count, sum as spark_sum,
    lag, lead, datediff, to_date, concat_ws, coalesce, min as spark_min,
    max as spark_max, stddev, row_number, floor, percentile_approx
)
from pyspark.sql.types import DoubleType, IntegerType
import logging

# ============================================================================
# Initialize Glue Context and Job
# ============================================================================

args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'SILVER_BUCKET',
    'GOLD_BUCKET',
    'DLQ_BUCKET',
    'DATABASE_NAME'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Job parameters
SILVER_BUCKET = args['SILVER_BUCKET']
GOLD_BUCKET = args['GOLD_BUCKET']
DLQ_BUCKET = args['DLQ_BUCKET']
DATABASE_NAME = args['DATABASE_NAME']
JOB_NAME = args['JOB_NAME']

logger.info(f"Starting job: {JOB_NAME}")
logger.info(f"Silver bucket: {SILVER_BUCKET}")
logger.info(f"Gold bucket: {GOLD_BUCKET}")
logger.info(f"DLQ bucket: {DLQ_BUCKET}")

# ============================================================================
# DLQ Error Handling Function
# ============================================================================

def write_to_dlq(failed_records, error_message, error_type, job_name, source_file="unknown"):
    """
    Write failed records to DLQ bucket with error metadata.
    
    Args:
        failed_records: DataFrame of failed records
        error_message: Description of the error
        error_type: Type of error
        job_name: Name of the Glue job
        source_file: Source file that caused the error
    """
    try:
        timestamp = datetime.now()
        year = timestamp.strftime("%Y")
        month = timestamp.strftime("%m")
        day = timestamp.strftime("%d")
        hour = timestamp.strftime("%H")
        
        # Add error metadata columns
        failed_with_metadata = failed_records.withColumn("error_message", lit(error_message)) \
            .withColumn("error_type", lit(error_type)) \
            .withColumn("job_name", lit(job_name)) \
            .withColumn("source_file", lit(source_file)) \
            .withColumn("error_timestamp", lit(timestamp.isoformat()))
        
        # Write to DLQ with partitioning
        dlq_path = f"s3://{DLQ_BUCKET}/feature_eng_errors/{year}/{month}/{day}/{hour}/"
        
        failed_with_metadata.write \
            .mode("append") \
            .parquet(dlq_path)
        
        logger.error(f"Wrote {failed_records.count()} failed records to DLQ: {dlq_path}")
        logger.error(f"Error: {error_message}")
        
    except Exception as e:
        logger.error(f"Failed to write to DLQ: {str(e)}")
        raise

# ============================================================================
# Feature Engineering Functions
# TODO: Decide on final features to engineer and implement them here
# ============================================================================

def calculate_delay_rate_metrics(df):
    """
    Calculate delay rate metrics by carrier, route, and time.
    Uses null-safe operations.
    """
    logger.info("Calculating delay rate metrics")
    
    try:
        # Define delay threshold (15 minutes)
        delay_threshold = 15
        
        # Create delay flag (null-safe)
        df = df.withColumn(
            "is_delayed",
            when(
                (col("ArrDelay").isNotNull()) & (col("ArrDelay") > delay_threshold),
                1
            ).otherwise(0)
        )
        
        # Carrier delay rate
        carrier_window = Window.partitionBy("UniqueCarrier")
        df = df.withColumn(
            "carrier_delay_rate",
            spark_sum("is_delayed").over(carrier_window) / count("*").over(carrier_window)
        )
        
        # Route delay rate (Origin-Dest pair)
        route_window = Window.partitionBy("Origin", "Dest")
        df = df.withColumn(
            "route_delay_rate",
            spark_sum("is_delayed").over(route_window) / count("*").over(route_window)
        )
        
        # Time-based delay rate (Month + DayOfWeek)
        time_window = Window.partitionBy("Month", "DayOfWeek")
        df = df.withColumn(
            "time_delay_rate",
            spark_sum("is_delayed").over(time_window) / count("*").over(time_window)
        )
        
        # Carrier-route combination delay rate
        carrier_route_window = Window.partitionBy("UniqueCarrier", "Origin", "Dest")
        df = df.withColumn(
            "carrier_route_delay_rate",
            spark_sum("is_delayed").over(carrier_route_window) / count("*").over(carrier_route_window)
        )
        
        logger.info("Delay rate metrics calculated successfully")
        return df
        
    except Exception as e:
        error_msg = f"Error calculating delay rate metrics: {str(e)}"
        logger.error(error_msg)
        write_to_dlq(df, error_msg, "feature_calculation_error", JOB_NAME)
        raise

def calculate_rolling_averages(df):
    """
    Compute rolling averages for delay metrics.
    Uses 7-day and 30-day windows.
    """
    logger.info("Calculating rolling averages")
    
    try:
        # Create date column for windowing
        df = df.withColumn(
            "flight_date",
            to_date(concat_ws("-", col("Year"), col("Month"), col("DayofMonth")))
        )
        
        # Define windows for rolling calculations
        # 7-day window
        window_7d = Window.partitionBy("UniqueCarrier") \
            .orderBy(col("flight_date").cast("long")) \
            .rangeBetween(-7 * 86400, 0)  # 7 days in seconds
        
        # 30-day window
        window_30d = Window.partitionBy("UniqueCarrier") \
            .orderBy(col("flight_date").cast("long")) \
            .rangeBetween(-30 * 86400, 0)  # 30 days in seconds
        
        # Calculate rolling averages (null-safe)
        df = df.withColumn(
            "rolling_avg_delay_7d",
            avg(col("ArrDelay")).over(window_7d)
        ).withColumn(
            "rolling_avg_delay_30d",
            avg(col("ArrDelay")).over(window_30d)
        )
        
        # Calculate rolling standard deviation
        df = df.withColumn(
            "rolling_stddev_delay_7d",
            stddev(col("ArrDelay")).over(window_7d)
        ).withColumn(
            "rolling_stddev_delay_30d",
            stddev(col("ArrDelay")).over(window_30d)
        )
        
        # Calculate rolling count of flights
        df = df.withColumn(
            "rolling_flight_count_7d",
            count("*").over(window_7d)
        ).withColumn(
            "rolling_flight_count_30d",
            count("*").over(window_30d)
        )
        
        logger.info("Rolling averages calculated successfully")
        return df
        
    except Exception as e:
        error_msg = f"Error calculating rolling averages: {str(e)}"
        logger.error(error_msg)
        write_to_dlq(df, error_msg, "rolling_avg_error", JOB_NAME)
        raise

def create_holiday_impact_features(df, holiday_df=None):
    """
    Create holiday impact flags using scraped Wikipedia holiday data.
    Null-safe operations for joins.
    """
    logger.info("Creating holiday impact features")
    
    try:
        # If no holiday data provided, try to load from Silver bucket
        if holiday_df is None:
            try:
                holiday_path = f"s3://{SILVER_BUCKET}/"
                all_data = spark.read.parquet(holiday_path)
                
                # Filter for holiday data
                holiday_df = all_data.filter(col("data_source") == "scraped")
                
                if holiday_df.count() == 0:
                    logger.warning("No holiday data found, skipping holiday features")
                    # Add placeholder holiday columns
                    df = df.withColumn("is_holiday", lit(0)) \
                           .withColumn("days_to_holiday", lit(None).cast("integer")) \
                           .withColumn("days_from_holiday", lit(None).cast("integer"))
                    return df
                    
            except Exception as e:
                logger.warning(f"Could not load holiday data: {str(e)}")
                # Add placeholder holiday columns
                df = df.withColumn("is_holiday", lit(0)) \
                       .withColumn("days_to_holiday", lit(None).cast("integer")) \
                       .withColumn("days_from_holiday", lit(None).cast("integer"))
                return df
        
        # Create flight date column
        df = df.withColumn(
            "flight_date",
            to_date(concat_ws("-", col("Year"), col("Month"), col("DayofMonth")))
        )
        
        # Assume holiday_df has a 'holiday_date' column
        # Join with holiday data (left join to keep all flight records)
        if "holiday_date" in holiday_df.columns:
            df_with_holidays = df.join(
                holiday_df.select("holiday_date").distinct(),
                df["flight_date"] == holiday_df["holiday_date"],
                "left"
            )
            
            # Create is_holiday flag
            df_with_holidays = df_with_holidays.withColumn(
                "is_holiday",
                when(col("holiday_date").isNotNull(), 1).otherwise(0)
            )
            
            # Calculate days to/from nearest holiday (simplified version)
            # In production, this would be more sophisticated
            df_with_holidays = df_with_holidays.withColumn(
                "days_to_holiday",
                lit(None).cast("integer")  # Placeholder
            ).withColumn(
                "days_from_holiday",
                lit(None).cast("integer")  # Placeholder
            )
            
            logger.info("Holiday impact features created successfully")
            return df_with_holidays
        else:
            logger.warning("Holiday data missing 'holiday_date' column")
            df = df.withColumn("is_holiday", lit(0)) \
                   .withColumn("days_to_holiday", lit(None).cast("integer")) \
                   .withColumn("days_from_holiday", lit(None).cast("integer"))
            return df
        
    except Exception as e:
        error_msg = f"Error creating holiday features: {str(e)}"
        logger.error(error_msg)
        # Don't fail the entire job, just log and continue
        df = df.withColumn("is_holiday", lit(0)) \
               .withColumn("days_to_holiday", lit(None).cast("integer")) \
               .withColumn("days_from_holiday", lit(None).cast("integer"))
        return df

def create_weather_correlation_features(df):
    """
    Generate weather correlation features (placeholder for future weather data).
    """
    logger.info("Creating weather correlation features (placeholder)")
    
    try:
        # Placeholder for weather features
        # In production, this would join with actual weather data
        df = df.withColumn("weather_delay_correlation", lit(None).cast(DoubleType())) \
               .withColumn("temperature_impact", lit(None).cast(DoubleType())) \
               .withColumn("precipitation_impact", lit(None).cast(DoubleType()))
        
        logger.info("Weather correlation features created (placeholders)")
        return df
        
    except Exception as e:
        logger.warning(f"Error creating weather features: {str(e)}")
        return df

def create_historical_event_features(df):
    """
    Create historical event correlation features using scraped data.
    """
    logger.info("Creating historical event features")
    
    try:
        # Placeholder for historical event features
        # In production, this would correlate with major events from scraped data
        df = df.withColumn("major_event_flag", lit(0)) \
               .withColumn("event_impact_score", lit(None).cast(DoubleType()))
        
        logger.info("Historical event features created")
        return df
        
    except Exception as e:
        logger.warning(f"Error creating historical event features: {str(e)}")
        return df

def enrich_operational_indicators(df):
    """
    Add indicators required to support cascade and reliability analytics.
    """
    logger.info("Enriching dataset with operational indicators")

    try:
        # Ensure cancelled column exists
        if "Cancelled" not in df.columns:
            df = df.withColumn("Cancelled", lit(0).cast(IntegerType()))

        # Ensure flight_date exists
        if "flight_date" not in df.columns:
            df = df.withColumn(
                "flight_date",
                to_date(concat_ws("-", col("Year"), col("Month"), col("DayofMonth")))
            )

        # Create CRS departure time as integer and derive flight hour buckets
        df = df.withColumn(
            "crs_dep_time_int",
            col("CRSDepTime").cast(IntegerType())
        ).withColumn(
            "flight_hour",
            when(
                col("crs_dep_time_int").isNotNull(),
                floor(col("crs_dep_time_int") / lit(100))
            ).otherwise(lit(None).cast(IntegerType()))
        )

        # Reliability flags
        df = df.withColumn(
            "cancelled_flag",
            when(col("Cancelled") == 1, 1).otherwise(0)
        ).withColumn(
            "on_time_flag",
            when(
                (col("ArrDelay").isNotNull()) &
                (col("ArrDelay") <= 15) &
                (col("cancelled_flag") == 0),
                1
            ).otherwise(0)
        )

        # Cascade indicators
        df = df.withColumn(
            "cascade_trigger_flag",
            when((col("DepDelay").isNotNull()) & (col("DepDelay") > 30), 1).otherwise(0)
        )

        tail_window = Window.partitionBy("TailNum", "flight_date") \
            .orderBy(col("crs_dep_time_int"))

        df = df.withColumn(
            "next_dep_delay_same_tail",
            lead("DepDelay").over(tail_window)
        ).withColumn(
            "cascade_follow_flag",
            when(
                (col("cascade_trigger_flag") == 1) &
                (col("next_dep_delay_same_tail").isNotNull()) &
                (col("next_dep_delay_same_tail") > 15),
                1
            ).otherwise(0)
        )

        # Composite reliability score (bounded 0-1)
        df = df.withColumn(
            "reliability_score_raw",
            when(col("cancelled_flag") == 1, lit(0.0)).otherwise(
                (col("on_time_flag") * 0.6) +
                (1 - coalesce(col("carrier_delay_rate"), lit(0.0))) * 0.2 +
                (1 - coalesce(col("route_delay_rate"), lit(0.0))) * 0.2
            )
        ).withColumn(
            "reliability_score",
            when(col("reliability_score_raw") < 0, lit(0.0))
            .when(col("reliability_score_raw") > 1, lit(1.0))
            .otherwise(col("reliability_score_raw"))
        )

        logger.info("Operational indicators added successfully")
        return df

    except Exception as e:
        logger.warning(f"Error enriching operational indicators: {str(e)}")
        return df

def build_cascade_metrics(df):
    """
    Aggregate cascading delay insights for airline operations teams.
    """
    logger.info("Building cascade metrics dataset")

    try:
        base_agg = df.groupBy("Year", "Month", "UniqueCarrier", "Origin", "Dest") \
            .agg(
                count("*").alias("flight_count"),
                spark_sum("cascade_trigger_flag").alias("cascade_triggers"),
                spark_sum("cascade_follow_flag").alias("cascade_events"),
                spark_sum("is_delayed").alias("arrival_delay_events"),
                spark_sum("on_time_flag").alias("on_time_events"),
                avg("ArrDelay").alias("avg_arrival_delay"),
                avg("DepDelay").alias("avg_departure_delay"),
                avg("rolling_avg_delay_30d").alias("rolling_avg_arrival_delay_30d"),
                spark_max("rolling_flight_count_30d").alias("max_flight_volume_30d")
            )

        cascade_metrics = base_agg \
            .withColumn(
                "cascade_rate",
                when(col("flight_count") > 0,
                     col("cascade_events") / col("flight_count")).otherwise(lit(0.0))
            ).withColumn(
                "cascade_propagation_ratio",
                when(col("cascade_triggers") > 0,
                     col("cascade_events") / col("cascade_triggers")).otherwise(lit(0.0))
            ).withColumn(
                "arrival_delay_rate",
                when(col("flight_count") > 0,
                     col("arrival_delay_events") / col("flight_count")).otherwise(lit(0.0))
            ).withColumn(
                "on_time_rate",
                when(col("flight_count") > 0,
                     col("on_time_events") / col("flight_count")).otherwise(lit(0.0))
            ).withColumn(
                "snapshot_ts",
                current_timestamp()
            )

        return cascade_metrics

    except Exception as e:
        logger.error(f"Error building cascade metrics: {str(e)}")
        write_to_dlq(df, f"Failed to build cascade metrics: {str(e)}",
                     "aggregation_error", JOB_NAME)
        return None

def build_reliability_metrics(df):
    """
    Aggregate traveler-facing reliability metrics.
    """
    logger.info("Building reliability metrics dataset")

    try:
        reliability_agg = df.groupBy(
            "Year", "Month", "UniqueCarrier", "Origin", "Dest", "flight_hour"
        ).agg(
            count("*").alias("flight_count"),
            spark_sum("on_time_flag").alias("on_time_flights"),
            spark_sum("cancelled_flag").alias("cancelled_flights"),
            avg("reliability_score").alias("avg_reliability_score"),
            percentile_approx("ArrDelay", 0.5, 100).alias("median_arrival_delay"),
            percentile_approx("ArrDelay", 0.8, 100).alias("p80_arrival_delay"),
            avg("ArrDelay").alias("avg_arrival_delay"),
            avg("DepDelay").alias("avg_departure_delay"),
            avg("carrier_delay_rate").alias("carrier_delay_rate"),
            avg("route_delay_rate").alias("route_delay_rate"),
            avg("time_delay_rate").alias("time_delay_rate")
        )

        reliability_metrics = reliability_agg \
            .withColumn(
                "on_time_rate",
                when(col("flight_count") > 0,
                     col("on_time_flights") / col("flight_count")).otherwise(lit(0.0))
            ).withColumn(
                "cancellation_rate",
                when(col("flight_count") > 0,
                     col("cancelled_flights") / col("flight_count")).otherwise(lit(0.0))
            ).withColumn(
                "reliability_band",
                when(col("on_time_rate") >= 0.85, lit("high"))
                .when(col("on_time_rate") >= 0.7, lit("medium"))
                .otherwise(lit("low"))
            ).withColumn(
                "snapshot_ts",
                current_timestamp()
            )

        return reliability_metrics

    except Exception as e:
        logger.error(f"Error building reliability metrics: {str(e)}")
        write_to_dlq(df, f"Failed to build reliability metrics: {str(e)}",
                     "aggregation_error", JOB_NAME)
        return None

def calculate_feature_statistics(df):
    """
    Calculate and log statistics for engineered features.
    """
    logger.info("Calculating feature statistics")
    
    try:
        # Select numeric feature columns
        feature_columns = [
            "carrier_delay_rate",
            "route_delay_rate",
            "time_delay_rate",
            "rolling_avg_delay_7d",
            "rolling_avg_delay_30d",
            "ArrDelay",
            "DepDelay"
        ]
        
        for col_name in feature_columns:
            if col_name in df.columns:
                stats = df.select(col_name).summary("min", "max", "mean", "stddev")
                
                min_val = stats.filter(col("summary") == "min").select(col_name).first()[0]
                max_val = stats.filter(col("summary") == "max").select(col_name).first()[0]
                mean_val = stats.filter(col("summary") == "mean").select(col_name).first()[0]
                stddev_val = stats.filter(col("summary") == "stddev").select(col_name).first()[0]
                
                logger.info(f"Feature: {col_name}")
                logger.info(f"  Min: {min_val}, Max: {max_val}, Mean: {mean_val}, StdDev: {stddev_val}")
        
    except Exception as e:
        logger.warning(f"Error calculating feature statistics: {str(e)}")

# ============================================================================
# Main Processing Logic
# ============================================================================

def read_silver_data():
    """
    Read cleaned data from Silver bucket.
    """
    logger.info("Reading data from Silver bucket")
    
    try:
        silver_path = f"s3://{SILVER_BUCKET}/"
        
        df = spark.read.parquet(silver_path)
        
        # Filter for flight delay data (not supplemental or scraped)
        df = df.filter(col("data_source") == "historical")
        
        logger.info(f"Read {df.count()} records from Silver bucket")
        return df
        
    except Exception as e:
        logger.error(f"Error reading from Silver bucket: {str(e)}")
        raise

def write_to_gold(df, subdirectory, partition_cols=None):
    """
    Write feature-engineered data to Gold bucket in Parquet format.
    """
    logger.info(f"Writing data to Gold bucket path: {subdirectory}")
    
    try:
        gold_path = f"s3://{GOLD_BUCKET}/{subdirectory}/"
        
        writer = df.write.mode("append")

        if partition_cols:
            writer = writer.partitionBy(*partition_cols)

        writer.parquet(gold_path)

        logger.info(f"Successfully wrote {df.count()} records to Gold bucket at {gold_path}")
        
    except Exception as e:
        logger.error(f"Error writing to Gold bucket: {str(e)}")
        write_to_dlq(df, f"Failed to write to Gold: {str(e)}", "write_error", JOB_NAME)
        raise

# ============================================================================
# Main Execution
# ============================================================================

try:
    logger.info("=" * 80)
    logger.info("Starting Feature Engineering Job")
    logger.info("=" * 80)
    
    # Read data from Silver bucket
    df = read_silver_data()
    
    if df is None or df.count() == 0:
        logger.warning("No data found in Silver bucket, exiting")
        job.commit()
        sys.exit(0)
    
    # Apply feature engineering transformations
    logger.info("Applying feature engineering transformations")
    
    # 1. Calculate delay rate metrics
    df = calculate_delay_rate_metrics(df)
    
    # 2. Calculate rolling averages
    df = calculate_rolling_averages(df)
    
    # 3. Create holiday impact features
    df = create_holiday_impact_features(df)
    
    # 4. Create weather correlation features (placeholder)
    df = create_weather_correlation_features(df)
    
    # 5. Create historical event features
    df = create_historical_event_features(df)
    
    # Add feature engineering metadata
    df = df.withColumn("feature_eng_timestamp", current_timestamp()) \
           .withColumn("target_layer", lit("gold"))

    # Enrich with operational indicators used for downstream aggregates
    df = enrich_operational_indicators(df)
    
    # Calculate and log feature statistics
    calculate_feature_statistics(df)
    
    # Write enriched flight-level features to Gold
    write_to_gold(df, "flight_features", partition_cols=["Year", "Month"])

    # Build and write cascade metrics
    cascade_metrics_df = build_cascade_metrics(df)
    if cascade_metrics_df is not None:
        write_to_gold(cascade_metrics_df, "cascade_metrics", partition_cols=["Year", "Month"])

    # Build and write reliability metrics
    reliability_metrics_df = build_reliability_metrics(df)
    if reliability_metrics_df is not None:
        write_to_gold(
            reliability_metrics_df,
            "reliability_metrics",
            partition_cols=["Year", "Month", "flight_hour"]
        )
    
    logger.info("=" * 80)
    logger.info("Feature Engineering Job Completed Successfully")
    logger.info("=" * 80)
    
    job.commit()

except Exception as e:
    logger.error(f"Job failed with error: {str(e)}")
    logger.error("Traceback:", exc_info=True)
    raise

