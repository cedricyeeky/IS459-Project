"""
Glue Job 1: Data Cleaning & Validation
========================================
This script reads data from the Raw S3 bucket, performs data cleaning and validation,
and writes the cleaned data to the Silver bucket in Parquet format.
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
from pyspark.sql import DataFrame
from pyspark.sql.functions import col, when, lit, current_timestamp, abs as spark_abs, input_file_name
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, DoubleType, TimestampType
import logging

# ============================================================================
# Initialize Glue Context and Job
# ============================================================================

args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'RAW_BUCKET',
    'SILVER_BUCKET',
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
RAW_BUCKET = args['RAW_BUCKET']
SILVER_BUCKET = args['SILVER_BUCKET']
DLQ_BUCKET = args['DLQ_BUCKET']
DATABASE_NAME = args['DATABASE_NAME']
JOB_NAME = args['JOB_NAME']

logger.info(f"Starting job: {JOB_NAME}")
logger.info(f"Raw bucket: {RAW_BUCKET}")
logger.info(f"Silver bucket: {SILVER_BUCKET}")
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
        error_type: Type of error (e.g., 'schema_validation', 'data_quality')
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
        dlq_path = f"s3://{DLQ_BUCKET}/cleaning_errors/{year}/{month}/{day}/{hour}/"
        
        failed_with_metadata.write \
            .mode("append") \
            .parquet(dlq_path)
        
        logger.error(f"Wrote {failed_records.count()} failed records to DLQ: {dlq_path}")
        logger.error(f"Error: {error_message}")
        
    except Exception as e:
        logger.error(f"Failed to write to DLQ: {str(e)}")
        raise

# ============================================================================
# Schema Definitions
# ============================================================================

# Expected schema for flight delay data
flight_delay_schema = StructType([
    StructField("Year", IntegerType(), True),
    StructField("Month", IntegerType(), True),
    StructField("DayofMonth", IntegerType(), True),
    StructField("DayOfWeek", IntegerType(), True),
    StructField("DepTime", StringType(), True),
    StructField("CRSDepTime", IntegerType(), True),
    StructField("ArrTime", StringType(), True),
    StructField("CRSArrTime", IntegerType(), True),
    StructField("UniqueCarrier", StringType(), True),
    StructField("FlightNum", IntegerType(), True),
    StructField("TailNum", StringType(), True),
    StructField("ActualElapsedTime", DoubleType(), True),
    StructField("CRSElapsedTime", DoubleType(), True),
    StructField("AirTime", DoubleType(), True),
    StructField("ArrDelay", DoubleType(), True),
    StructField("DepDelay", DoubleType(), True),
    StructField("Origin", StringType(), True),
    StructField("Dest", StringType(), True),
    StructField("Distance", DoubleType(), True),
    StructField("TaxiIn", DoubleType(), True),
    StructField("TaxiOut", DoubleType(), True),
    StructField("Cancelled", IntegerType(), True),
    StructField("CancellationCode", StringType(), True),
    StructField("Diverted", IntegerType(), True),
])

# ============================================================================
# Data Quality Functions
# ============================================================================

def validate_schema(df, expected_schema, source_name):
    """
    Validate that DataFrame matches expected schema.
    """
    logger.info(f"Validating schema for {source_name}")
    
    # Check if all required columns exist
    df_columns = set(df.columns)
    expected_columns = set([field.name for field in expected_schema.fields])
    
    missing_columns = expected_columns - df_columns
    if missing_columns:
        error_msg = f"Missing columns in {source_name}: {missing_columns}"
        logger.error(error_msg)
        # Write entire dataframe to DLQ as it's invalid
        write_to_dlq(df, error_msg, "schema_validation", JOB_NAME, source_name)
        return None
    
    logger.info(f"Schema validation passed for {source_name}")
    return df

def detect_outliers(df, column_name, z_threshold=3.0):
    """
    Detect outliers using Z-score method.
    Flag records with Z-score > threshold.
    """
    logger.info(f"Detecting outliers in column: {column_name}")
    
    # Calculate mean and standard deviation
    stats = df.select(
        spark_abs(col(column_name)).alias("value")
    ).summary("mean", "stddev")
    
    mean_val = float(stats.filter(col("summary") == "mean").select("value").first()[0])
    stddev_val = float(stats.filter(col("summary") == "stddev").select("value").first()[0])
    
    if stddev_val == 0:
        logger.warning(f"Standard deviation is 0 for {column_name}, skipping outlier detection")
        return df
    
    # Calculate Z-score and flag outliers
    df_with_zscore = df.withColumn(
        f"{column_name}_zscore",
        spark_abs((col(column_name) - lit(mean_val)) / lit(stddev_val))
    ).withColumn(
        f"{column_name}_is_outlier",
        when(col(f"{column_name}_zscore") > z_threshold, True).otherwise(False)
    )
    
    outlier_count = df_with_zscore.filter(col(f"{column_name}_is_outlier") == True).count()
    logger.info(f"Found {outlier_count} outliers in {column_name}")
    
    return df_with_zscore

def handle_null_values(df):
    """
    Handle null values in critical columns.
    """
    logger.info("Handling null values")
    
    # Define critical columns that should not be null
    critical_columns = ["Year", "Month", "DayofMonth", "Origin", "Dest", "UniqueCarrier"]
    
    # Filter out records with nulls in critical columns
    null_filter = None
    for col_name in critical_columns:
        if col_name in df.columns:
            if null_filter is None:
                null_filter = col(col_name).isNull()
            else:
                null_filter = null_filter | col(col_name).isNull()
    
    if null_filter is not None:
        # Separate null records for DLQ
        null_records = df.filter(null_filter)
        null_count = null_records.count()
        
        if null_count > 0:
            logger.warning(f"Found {null_count} records with null critical values")
            write_to_dlq(
                null_records,
                "Null values in critical columns",
                "null_validation",
                JOB_NAME,
                "multiple_sources"
            )
        
        # Keep only valid records
        valid_df = df.filter(~null_filter)
        logger.info(f"Retained {valid_df.count()} valid records after null filtering")
        return valid_df
    
    return df

def deduplicate_data(df, key_columns=None):
    """
    Remove duplicate records based on key columns.
    
    Args:
        df: DataFrame to deduplicate
        key_columns: List of column names to use as deduplication keys.
                    If None, deduplicate across all columns.
    
    Returns:
        Deduplicated DataFrame
    """
    logger.info("Deduplicating data")
    
    initial_count = df.count()
    
    if key_columns is None:
        # Deduplicate across all columns
        deduped_df = df.dropDuplicates()
        logger.info("Deduplicating across all columns")
    else:
        # Filter key_columns to only include columns that exist in DataFrame
        existing_keys = [col for col in key_columns if col in df.columns]
        
        if not existing_keys:
            logger.warning(f"None of the specified key columns {key_columns} exist in DataFrame. Skipping deduplication.")
            return df
        
        if len(existing_keys) < len(key_columns):
            missing_keys = set(key_columns) - set(existing_keys)
            logger.warning(f"Some key columns missing: {missing_keys}. Using available columns: {existing_keys}")
        
        deduped_df = df.dropDuplicates(existing_keys)
        logger.info(f"Deduplicating using columns: {existing_keys}")
    
    final_count = deduped_df.count()
    duplicates_removed = initial_count - final_count
    
    logger.info(f"Removed {duplicates_removed} duplicate records")
    logger.info(f"Retained {final_count} unique records")
    
    return deduped_df

# ============================================================================
# Main Processing Logic
# ============================================================================

def process_historical_data():
    """
    Process historical flight delay data from Raw bucket.
    """
    logger.info("Processing historical data")
    
    try:
        historical_path = f"s3://{RAW_BUCKET}/historical/"
        
        # Read CSV files
        df = spark.read \
            .option("header", "true") \
            .option("inferSchema", "true") \
            .csv(historical_path)
        
        logger.info(f"Read {df.count()} records from historical data")
        
        # Validate schema
        df = validate_schema(df, flight_delay_schema, "historical_data")
        if df is None:
            return None
        
        # Handle null values
        df = handle_null_values(df)
        
        # Deduplicate using flight-specific key columns
        df = deduplicate_data(df, ["Year", "Month", "DayofMonth", "FlightNum", "UniqueCarrier", "Origin", "Dest"])
        
        # Detect outliers in delay columns
        if "ArrDelay" in df.columns:
            df = detect_outliers(df, "ArrDelay", z_threshold=3.0)
        
        if "DepDelay" in df.columns:
            df = detect_outliers(df, "DepDelay", z_threshold=3.0)
        
        # Add processing metadata
        df = df.withColumn("processing_timestamp", current_timestamp()) \
               .withColumn("source_layer", lit("raw")) \
               .withColumn("data_source", lit("historical"))
        
        logger.info(f"Historical data processing complete: {df.count()} records")
        return df
        
    except Exception as e:
        logger.error(f"Error processing historical data: {str(e)}")
        raise

def process_supplemental_data():
    """
    Process supplemental data (weather data, terrorism data, plane data, FAA enplanements).
    Handles different data types from subdirectories with appropriate deduplication strategies.
    Returns a dictionary with separate dataframes for each type: {'weather': df, 'terrorism': df, 'supplemental': df}
    """
    logger.info("Processing supplemental data")
    
    results = {}
    
    # ============================================================================
    # Process Weather Data from supplemental/weather/
    # ============================================================================
    try:
        weather_path = f"s3://{RAW_BUCKET}/supplemental/weather/"
        logger.info(f"Reading weather data from {weather_path}")
        
        weather_df = spark.read \
            .option("header", "true") \
            .option("inferSchema", "true") \
            .csv(weather_path)
        
        weather_count = weather_df.count()
        logger.info(f"Read {weather_count} records from weather data")
        
        if weather_count > 0:
            # Weather data deduplication using obs_id and valid_time_gmt
            if "obs_id" in weather_df.columns and "valid_time_gmt" in weather_df.columns:
                weather_df = deduplicate_data(weather_df, ["obs_id", "valid_time_gmt"])
                logger.info("Deduplicated weather data using obs_id and valid_time_gmt")
            else:
                logger.warning("Weather data missing obs_id or valid_time_gmt columns, using generic deduplication")
                weather_df = deduplicate_data(weather_df)
            
            # Add processing metadata
            weather_df = weather_df.withColumn("processing_timestamp", current_timestamp()) \
                                   .withColumn("source_layer", lit("raw")) \
                                   .withColumn("data_source", lit("supplemental")) \
                                   .withColumn("data_type", lit("weather"))
            
            results['weather'] = weather_df
            logger.info(f"Weather data processing complete: {weather_count} records")
        else:
            logger.info("No weather data found")
            
    except Exception as e:
        logger.warning(f"Error processing weather data (may not exist): {str(e)}")
    
    # ============================================================================
    # Process Terrorism/Security Data from supplemental/security/
    # ============================================================================
    try:
        security_path = f"s3://{RAW_BUCKET}/supplemental/security/"
        logger.info(f"Reading terrorism data from {security_path}")
        
        terrorism_df = spark.read \
            .option("header", "true") \
            .option("inferSchema", "true") \
            .csv(security_path)
        
        terrorism_count = terrorism_df.count()
        logger.info(f"Read {terrorism_count} records from terrorism data")
        
        if terrorism_count > 0:
            # Terrorism data deduplication - use date columns if available
            dedup_cols = []
            if "iyear" in terrorism_df.columns and "imonth" in terrorism_df.columns and "iday" in terrorism_df.columns:
                # Global Terrorism Database format
                dedup_cols = ["iyear", "imonth", "iday", "country", "city", "latitude", "longitude"]
                logger.info("Detected Global Terrorism Database format")
            elif "event_date" in terrorism_df.columns:
                dedup_cols = ["event_date", "location"]
                logger.info("Detected event_date format")
            elif "date" in terrorism_df.columns:
                dedup_cols = ["date", "location"]
                logger.info("Detected date format")
            
            if dedup_cols:
                # Filter to only existing columns
                existing_dedup_cols = [c for c in dedup_cols if c in terrorism_df.columns]
                if existing_dedup_cols:
                    terrorism_df = deduplicate_data(terrorism_df, existing_dedup_cols)
                    logger.info(f"Deduplicated terrorism data using columns: {existing_dedup_cols}")
                else:
                    terrorism_df = deduplicate_data(terrorism_df)
                    logger.warning("None of the expected deduplication columns found, using generic deduplication")
            else:
                terrorism_df = deduplicate_data(terrorism_df)
                logger.info("Using generic deduplication for terrorism data")
            
            # Add processing metadata
            terrorism_df = terrorism_df.withColumn("processing_timestamp", current_timestamp()) \
                                      .withColumn("source_layer", lit("raw")) \
                                      .withColumn("data_source", lit("supplemental")) \
                                      .withColumn("data_type", lit("terrorism"))
            
            results['terrorism'] = terrorism_df
            logger.info(f"Terrorism data processing complete: {terrorism_count} records")
        else:
            logger.info("No terrorism data found")
            
    except Exception as e:
        logger.warning(f"Error processing terrorism data (may not exist): {str(e)}")
    
    # ============================================================================
    # Process Other Supplemental Data from root supplemental/ directory
    # (plane data, FAA enplanements, etc.)
    # ============================================================================
    try:
        supplemental_path = f"s3://{RAW_BUCKET}/supplemental/"
        logger.info(f"Reading other supplemental data from {supplemental_path}")
        
        # Read all files from supplemental/ directory
        other_df = spark.read \
            .option("header", "true") \
            .option("inferSchema", "true") \
            .csv(supplemental_path)
        
        # Add file path column to filter out subdirectories
        other_df = other_df.withColumn("file_path", input_file_name())
        
        # Filter out files from weather/ and security/ subdirectories
        other_df = other_df.filter(
            ~col("file_path").contains("/weather/") & 
            ~col("file_path").contains("/security/")
        )
        
        other_count = other_df.count()
        
        if other_count > 0:
            logger.info(f"Read {other_count} records from other supplemental data")
            
            # Remove the file_path column after filtering
            other_df = other_df.drop("file_path")
            
            # Detect data type and deduplicate accordingly
            if "tailnum" in other_df.columns or "TailNum" in other_df.columns:
                # Plane data
                logger.info("Detected plane data format")
                other_df = deduplicate_data(other_df)
            else:
                # Generic supplemental data - deduplicate across all columns
                logger.info("Using generic deduplication for other supplemental data")
                other_df = deduplicate_data(other_df)
            
            # Add processing metadata
            other_df = other_df.withColumn("processing_timestamp", current_timestamp()) \
                               .withColumn("source_layer", lit("raw")) \
                               .withColumn("data_source", lit("supplemental")) \
                               .withColumn("data_type", lit("other"))
            
            results['supplemental'] = other_df
            logger.info(f"Other supplemental data processing complete: {other_count} records")
        else:
            logger.info("No other supplemental data found in root supplemental/ directory")
            
    except Exception as e:
        logger.warning(f"Error processing other supplemental data (may not exist): {str(e)}")
    
    # ============================================================================
    # Return results dictionary
    # ============================================================================
    if results:
        total_records = sum([df.count() for df in results.values()])
        logger.info(f"Supplemental data processing complete: {total_records} total records")
        
        # Log breakdown by data type
        for data_type, df in results.items():
            count = df.count()
            logger.info(f"  - {data_type}: {count} records")
        
        return results
    else:
        logger.warning("No supplemental data processed")
        return None

# ============================================================================
# Scraped Data Processing - REMOVED
# ============================================================================
# Scraped/realtime data processing has been moved to a separate Glue job
# that handles real-time data ingestion from the Mock API.
# This job focuses on batch processing of historical and supplemental data.

def write_to_silver(df, partition_cols=None, subdirectory=None):
    """
    Write cleaned data to Silver bucket in Parquet format.
    
    Args:
        df: DataFrame to write
        partition_cols: List of columns to partition by
        subdirectory: Optional subdirectory path (e.g., 'weather', 'terrorism', 'supplemental', 'historical', 'scraped')
    """
    logger.info("Writing data to Silver bucket")
    
    try:
        if subdirectory:
            silver_path = f"s3://{SILVER_BUCKET}/{subdirectory}/"
            logger.info(f"Writing to subdirectory: {subdirectory}")
        else:
            silver_path = f"s3://{SILVER_BUCKET}/"
        
        record_count = df.count()
        
        if partition_cols:
            df.write \
                .mode("append") \
                .partitionBy(*partition_cols) \
                .parquet(silver_path)
        else:
            df.write \
                .mode("append") \
                .parquet(silver_path)
        
        logger.info(f"Successfully wrote {record_count} records to Silver bucket: {silver_path}")
        
    except Exception as e:
        logger.error(f"Error writing to Silver bucket: {str(e)}")
        write_to_dlq(df, f"Failed to write to Silver: {str(e)}", "write_error", JOB_NAME)
        raise

# ============================================================================
# Main Execution
# ============================================================================

try:
    logger.info("=" * 80)
    logger.info("Starting Data Cleaning Job")
    logger.info("=" * 80)
    
    # ============================================================================
    # Process Historical Data (Main Dataset)
    # ============================================================================
    logger.info("Processing historical flight data...")
    historical_df = process_historical_data()
    
    if historical_df is not None:
        record_count = historical_df.count()
        logger.info(f"Historical data ready to write: {record_count} records")
        # Write to Silver with partitioning in historical/ subdirectory
        write_to_silver(historical_df, partition_cols=["Year", "Month"], subdirectory="historical")
        logger.info("Historical data written successfully to s3://{}/historical/".format(SILVER_BUCKET))
    else:
        logger.warning("Historical data processing returned None - check logs above for errors")
        logger.warning("Possible causes: schema validation failed, no data in s3://{}/historical/, or processing error".format(RAW_BUCKET))
    
    # ============================================================================
    # Process Supplemental Data (Weather, Terrorism, Other)
    # ============================================================================
    logger.info("Processing supplemental data...")
    supplemental_results = process_supplemental_data()
    
    if supplemental_results:
        logger.info(f"Supplemental data processing returned {len(supplemental_results)} data types")
        
        # Write weather data to weather/ subdirectory
        if 'weather' in supplemental_results:
            weather_count = supplemental_results['weather'].count()
            logger.info(f"Weather data ready to write: {weather_count} records")
            write_to_silver(supplemental_results['weather'], subdirectory="weather")
            logger.info("Weather data written successfully to s3://{}/weather/".format(SILVER_BUCKET))
        else:
            logger.info("No weather data to write (may not exist in raw bucket)")
        
        # Write terrorism data to terrorism/ subdirectory
        if 'terrorism' in supplemental_results:
            terrorism_count = supplemental_results['terrorism'].count()
            logger.info(f"Terrorism data ready to write: {terrorism_count} records")
            write_to_silver(supplemental_results['terrorism'], subdirectory="terrorism")
            logger.info("Terrorism data written successfully to s3://{}/terrorism/".format(SILVER_BUCKET))
        else:
            logger.info("No terrorism data to write (may not exist in raw bucket)")
        
        # Write other supplemental data to supplemental/ subdirectory
        if 'supplemental' in supplemental_results:
            other_count = supplemental_results['supplemental'].count()
            logger.info(f"Other supplemental data ready to write: {other_count} records")
            write_to_silver(supplemental_results['supplemental'], subdirectory="supplemental")
            logger.info("Other supplemental data written successfully to s3://{}/supplemental/".format(SILVER_BUCKET))
        else:
            logger.info("No other supplemental data to write")
    else:
        logger.warning("No supplemental data processed - check if data exists in s3://{}/supplemental/".format(RAW_BUCKET))
        logger.warning("Expected paths: s3://{}/supplemental/weather/ and s3://{}/supplemental/security/".format(RAW_BUCKET, RAW_BUCKET))
    
    # ============================================================================
    # Scraped/Realtime Data Processing - REMOVED
    # ============================================================================
    # Scraped data from Mock API is now processed by a separate Glue job
    # that handles real-time data ingestion. This job focuses on batch processing.
    logger.info("Skipping scraped data processing (handled by separate real-time Glue job)")
    
    logger.info("=" * 80)
    logger.info("Data Cleaning Job Completed Successfully")
    logger.info("=" * 80)
    
    job.commit()

except Exception as e:
    logger.error(f"Job failed with error: {str(e)}")
    logger.error("Traceback:", exc_info=True)
    raise

