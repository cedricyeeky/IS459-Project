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
from pyspark.sql.functions import col, when, lit, current_timestamp, abs as spark_abs
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
    Process supplemental data (weather data, plane data, FAA enplanements).
    Handles different data types with appropriate deduplication strategies.
    """
    logger.info("Processing supplemental data")
    
    try:
        supplemental_path = f"s3://{RAW_BUCKET}/supplemental/"
        
        # Try to read supplemental data (may be CSV or Parquet)
        try:
            df = spark.read \
                .option("header", "true") \
                .option("inferSchema", "true") \
                .csv(supplemental_path)
            logger.info(f"Read {df.count()} records from supplemental CSV data")
        except:
            try:
                df = spark.read.parquet(supplemental_path)
                logger.info(f"Read {df.count()} records from supplemental Parquet data")
            except:
                logger.warning("No supplemental data found or unable to read")
                return None
        
        # Detect data type and deduplicate accordingly
        if "obs_id" in df.columns and "valid_time_gmt" in df.columns:
            # Weather data
            logger.info("Detected weather data format")
            df = deduplicate_data(df, ["obs_id", "valid_time_gmt"])
        elif "tailnum" in df.columns or "TailNum" in df.columns:
            # Plane data
            logger.info("Detected plane data format")
            # Use all columns for deduplication (or specify tailnum if it exists)
            df = deduplicate_data(df)
        else:
            # Generic supplemental data - deduplicate across all columns
            logger.info("Using generic deduplication for supplemental data")
            df = deduplicate_data(df)
        
        # Add processing metadata
        df = df.withColumn("processing_timestamp", current_timestamp()) \
               .withColumn("source_layer", lit("raw")) \
               .withColumn("data_source", lit("supplemental"))
        
        logger.info(f"Supplemental data processing complete: {df.count()} records")
        return df
        
    except Exception as e:
        logger.error(f"Error processing supplemental data: {str(e)}")
        return None

def process_scraped_data():
    """
    Process scraped Wikipedia data (holidays, events).
    """
    logger.info("Processing scraped data")
    
    try:
        scraped_path = f"s3://{RAW_BUCKET}/scraped/"
        
        # Read CSV files from scraping
        df = spark.read \
            .option("header", "true") \
            .option("inferSchema", "true") \
            .csv(scraped_path)
        
        logger.info(f"Read {df.count()} records from scraped data")
        
        # Deduplicate (important for scraped data) - use all columns
        df = deduplicate_data(df)
        
        # Add processing metadata
        df = df.withColumn("processing_timestamp", current_timestamp()) \
               .withColumn("source_layer", lit("raw")) \
               .withColumn("data_source", lit("scraped"))
        
        logger.info(f"Scraped data processing complete: {df.count()} records")
        return df
        
    except Exception as e:
        logger.warning(f"No scraped data found or error processing: {str(e)}")
        return None

def write_to_silver(df, partition_cols=None):
    """
    Write cleaned data to Silver bucket in Parquet format.
    """
    logger.info("Writing data to Silver bucket")
    
    try:
        silver_path = f"s3://{SILVER_BUCKET}/"
        
        if partition_cols:
            df.write \
                .mode("append") \
                .partitionBy(*partition_cols) \
                .parquet(silver_path)
        else:
            df.write \
                .mode("append") \
                .parquet(silver_path)
        
        logger.info(f"Successfully wrote {df.count()} records to Silver bucket")
        
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
    
    # Process historical data (main dataset)
    historical_df = process_historical_data()
    
    if historical_df is not None:
        # Write to Silver with partitioning
        write_to_silver(historical_df, partition_cols=["Year", "Month"])
    
    # Process supplemental data
    supplemental_df = process_supplemental_data()
    if supplemental_df is not None:
        write_to_silver(supplemental_df)
    
    # Process scraped data
    scraped_df = process_scraped_data()
    if scraped_df is not None:
        write_to_silver(scraped_df)
    
    logger.info("=" * 80)
    logger.info("Data Cleaning Job Completed Successfully")
    logger.info("=" * 80)
    
    job.commit()

except Exception as e:
    logger.error(f"Job failed with error: {str(e)}")
    logger.error("Traceback:", exc_info=True)
    raise

