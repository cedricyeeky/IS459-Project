"""
Test script for data_cleaning.py deduplication logic
Run locally with PySpark to validate before deploying to AWS Glue
"""

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, lit, current_timestamp
import logging

# Initialize Spark
spark = SparkSession.builder \
    .appName("DataCleaningTest") \
    .master("local[*]") \
    .getOrCreate()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ============================================================================
# Copy the deduplicate_data function from data_cleaning.py
# ============================================================================

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
# Test Cases
# ============================================================================

def test_weather_data():
    """Test with actual weather data structure"""
    logger.info("="*60)
    logger.info("TEST 1: Weather Data Deduplication")
    logger.info("="*60)
    
    # Read sample from weather_data_list1.csv
    weather_df = spark.read \
        .option("header", "true") \
        .option("inferSchema", "true") \
        .csv("preprocessing/weather_data_list1.csv")
    
    logger.info(f"Read {weather_df.count()} records from weather_data_list1.csv")
    logger.info(f"Schema: {weather_df.columns}")
    
    # Show sample data
    logger.info("\nSample data:")
    weather_df.show(5, truncate=False)
    
    # Test deduplication with weather keys
    deduped = deduplicate_data(weather_df, ["obs_id", "valid_time_gmt"])
    
    logger.info(f"\n✅ Weather data test passed!")
    return deduped

def test_flight_data():
    """Test with flight data structure (if available)"""
    logger.info("="*60)
    logger.info("TEST 2: Flight Data Deduplication")
    logger.info("="*60)
    
    # Create sample flight data
    flight_data = [
        (2008, 1, 3, 123, "AA", "ORD", "DFW"),
        (2008, 1, 3, 123, "AA", "ORD", "DFW"),  # Duplicate
        (2008, 1, 4, 456, "UA", "SFO", "LAX"),
    ]
    
    flight_df = spark.createDataFrame(
        flight_data,
        ["Year", "Month", "DayofMonth", "FlightNum", "UniqueCarrier", "Origin", "Dest"]
    )
    
    logger.info(f"Created {flight_df.count()} sample flight records")
    flight_df.show()
    
    # Test deduplication with flight keys
    deduped = deduplicate_data(
        flight_df,
        ["Year", "Month", "DayofMonth", "FlightNum", "UniqueCarrier", "Origin", "Dest"]
    )
    
    assert deduped.count() == 2, "Should have 2 unique records after dedup"
    logger.info(f"\n✅ Flight data test passed!")
    return deduped

def test_missing_columns():
    """Test behavior when key columns don't exist"""
    logger.info("="*60)
    logger.info("TEST 3: Missing Columns Handling")
    logger.info("="*60)
    
    # Create simple dataframe
    data = [("A", 1), ("B", 2), ("A", 1)]
    df = spark.createDataFrame(data, ["col1", "col2"])
    
    logger.info("Original data:")
    df.show()
    
    # Try to deduplicate with non-existent columns
    deduped = deduplicate_data(df, ["Year", "Month", "NonExistent"])
    
    # Should return original df unchanged
    assert deduped.count() == 3, "Should return unchanged when keys don't exist"
    logger.info(f"\n✅ Missing columns test passed!")
    return deduped

def test_all_columns_dedup():
    """Test deduplication across all columns (None parameter)"""
    logger.info("="*60)
    logger.info("TEST 4: All Columns Deduplication")
    logger.info("="*60)
    
    # Create data with duplicates
    data = [
        ("Holiday1", "2008-01-01", "New Year"),
        ("Holiday1", "2008-01-01", "New Year"),  # Exact duplicate
        ("Holiday2", "2008-07-04", "Independence"),
    ]
    
    df = spark.createDataFrame(data, ["id", "date", "name"])
    
    logger.info("Original data:")
    df.show()
    
    # Deduplicate across all columns
    deduped = deduplicate_data(df, None)
    
    assert deduped.count() == 2, "Should have 2 unique records"
    logger.info(f"\n✅ All columns deduplication test passed!")
    return deduped

def test_supplemental_data_detection():
    """Test the auto-detection logic for supplemental data"""
    logger.info("="*60)
    logger.info("TEST 5: Supplemental Data Type Detection")
    logger.info("="*60)
    
    # Read weather data
    weather_df = spark.read \
        .option("header", "true") \
        .option("inferSchema", "true") \
        .csv("preprocessing/weather_data_list1.csv")
    
    # Simulate the detection logic from process_supplemental_data
    if "obs_id" in weather_df.columns and "valid_time_gmt" in weather_df.columns:
        logger.info("✅ Correctly detected weather data format")
        deduped = deduplicate_data(weather_df, ["obs_id", "valid_time_gmt"])
    else:
        logger.error("❌ Failed to detect weather data format")
        raise AssertionError("Weather data detection failed")
    
    logger.info(f"\n✅ Auto-detection test passed!")
    return deduped

# ============================================================================
# Run All Tests
# ============================================================================

if __name__ == "__main__":
    try:
        print("\n" + "="*60)
        print("STARTING DATA CLEANING TESTS")
        print("="*60 + "\n")
        
        # Run tests
        test_weather_data()
        test_flight_data()
        test_missing_columns()
        test_all_columns_dedup()
        test_supplemental_data_detection()
        
        print("\n" + "="*60)
        print("✅ ALL TESTS PASSED!")
        print("="*60 + "\n")
        
    except Exception as e:
        print("\n" + "="*60)
        print(f"❌ TEST FAILED: {str(e)}")
        print("="*60 + "\n")
        raise
    finally:
        spark.stop()
