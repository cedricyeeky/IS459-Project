#!/usr/bin/env python3
"""
Script to create sample subsets of all datasets for end-to-end pipeline testing.
This will help test Glue jobs without processing the entire datasets.
Supports:
- Airline data (main dataset)
- Weather data (multiple files)
- Federal holidays
- US terrorism data
- Other supplemental data
"""

import random
import shutil
from pathlib import Path
from typing import List

def create_sample(input_file, output_file, num_rows=None, sample_ratio=None, 
                  skip_if_small=True, max_size_mb=10):
    """
    Create a sample of a CSV file.
    
    Args:
        input_file: Path to the input CSV file
        output_file: Path to save the sample
        num_rows: Number of rows to extract (if None and sample_ratio is None, copies entire file)
        sample_ratio: Alternative - sample every Nth row (e.g., 0.01 for 1%)
        skip_if_small: If True, copy entire file if it's smaller than max_size_mb
        max_size_mb: Maximum file size (MB) to copy entirely when skip_if_small=True
    """
    print(f"\n{'='*60}")
    print(f"Processing: {input_file}")
    print(f"{'='*60}")
    
    input_path = Path(input_file)
    output_path = Path(output_file)
    
    # Ensure output directory exists
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    if not input_path.exists():
        print(f"⚠ Warning: Input file {input_file} does not exist (skipping)")
        return False
    
    # Check if file is a Git LFS pointer
    try:
        with open(input_path, 'r', encoding='utf-8') as f:
            first_line = f.readline()
            if first_line.startswith('version https://git-lfs.github.com'):
                print(f"⚠ Warning: {input_file} is a Git LFS pointer file")
                print(f"   Please run 'git lfs pull' to download the actual file, or skip this file")
                return False
    except Exception:
        pass
    
    # Check file size
    file_size_mb = input_path.stat().st_size / (1024 * 1024)
    print(f"File size: {file_size_mb:.2f} MB")
    
    # If file is small and skip_if_small is True, just copy it
    if skip_if_small and file_size_mb < max_size_mb and num_rows is None and sample_ratio is None:
        print(f"File is small ({file_size_mb:.2f} MB < {max_size_mb} MB), copying entirely...")
        shutil.copy2(input_path, output_path)
        print(f"✓ Copied entire file to {output_path}")
        return True
    
    rows_written = 0
    rows_read = 0
    header_written = False
    
    try:
        with open(input_path, 'r', encoding='utf-8', errors='replace') as infile, \
             open(output_path, 'w', encoding='utf-8', newline='') as outfile:
            
            # Read and write header
            header = infile.readline()
            if not header.strip():
                print(f"⚠ Warning: Empty file or no header found")
                return False
            
            outfile.write(header)
            header_written = True
            print(f"Header: {header.strip()[:80]}...")
            
            if sample_ratio:
                # Sample by ratio (e.g., every 100th row for 0.01)
                random.seed(42)  # For reproducibility
                print(f"Sampling {sample_ratio*100}% of rows...")
                
                for line in infile:
                    rows_read += 1
                    if random.random() < sample_ratio:
                        outfile.write(line)
                        rows_written += 1
                    
                    if rows_read % 100000 == 0:
                        print(f"  Processed {rows_read:,} rows, sampled {rows_written:,} rows...")
            elif num_rows:
                # Sample first N rows
                print(f"Extracting first {num_rows:,} rows...")
                for line in infile:
                    rows_read += 1
                    outfile.write(line)
                    rows_written += 1
                    
                    if rows_written >= num_rows:
                        break
                    
                    if rows_read % 100000 == 0:
                        print(f"  Extracted {rows_written:,} rows...")
            else:
                # Copy entire file
                print("Copying entire file...")
                for line in infile:
                    rows_read += 1
                    outfile.write(line)
                    rows_written += 1
                    
                    if rows_read % 100000 == 0:
                        print(f"  Copied {rows_read:,} rows...")
        
        print(f"\n✓ Sample created successfully!")
        print(f"  Total rows read: {rows_read:,}")
        print(f"  Rows in sample: {rows_written:,}")
        print(f"  Output file: {output_path}")
        if output_path.exists():
            print(f"  File size: {output_path.stat().st_size / (1024*1024):.2f} MB")
        return True
        
    except Exception as e:
        print(f"✗ Error creating sample: {e}")
        import traceback
        traceback.print_exc()
        return False


def sample_weather_data(weather_files: List[str], output_dir: Path, 
                       sample_ratio: float = 0.01, combine: bool = True):
    """
    Sample weather data from multiple files.
    
    Args:
        weather_files: List of weather data file paths
        output_dir: Directory to save sampled weather data
        sample_ratio: Ratio to sample (default: 1%)
        combine: If True, combine all samples into one file; if False, sample each separately
    """
    print(f"\n{'='*60}")
    print(f"Processing Weather Data ({len(weather_files)} files)")
    print(f"{'='*60}")
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    if combine:
        # Combine all weather files into one sample
        output_file = output_dir / "weather_data_sample.csv"
        header_written = False
        
        with open(output_file, 'w', encoding='utf-8', newline='') as outfile:
            for weather_file in weather_files:
                weather_path = Path(weather_file)
                if not weather_path.exists():
                    print(f"⚠ Skipping {weather_file} (not found)")
                    continue
                
                print(f"\nProcessing {weather_path.name}...")
                random.seed(42)  # For reproducibility
                rows_sampled = 0
                rows_read = 0
                
                with open(weather_path, 'r', encoding='utf-8', errors='replace') as infile:
                    # Read header
                    header = infile.readline()
                    if not header_written:
                        outfile.write(header)
                        header_written = True
                    
                    # Sample rows
                    for line in infile:
                        rows_read += 1
                        if random.random() < sample_ratio:
                            outfile.write(line)
                            rows_sampled += 1
                        
                        if rows_read % 100000 == 0:
                            print(f"  Processed {rows_read:,} rows, sampled {rows_sampled:,}...")
                    
                    print(f"  ✓ Sampled {rows_sampled:,} rows from {rows_read:,} total")
        
        if output_file.exists():
            size_mb = output_file.stat().st_size / (1024 * 1024)
            print(f"\n✓ Combined weather sample: {output_file}")
            print(f"  File size: {size_mb:.2f} MB")
            return True
    else:
        # Sample each file separately
        success_count = 0
        for weather_file in weather_files:
            weather_path = Path(weather_file)
            if not weather_path.exists():
                continue
            
            output_file = output_dir / f"{weather_path.stem}_sample.csv"
            if create_sample(str(weather_path), str(output_file), sample_ratio=sample_ratio):
                success_count += 1
        
        print(f"\n✓ Sampled {success_count}/{len(weather_files)} weather files")
        return success_count > 0
    
    return False

if __name__ == "__main__":
    print("="*80)
    print("Sample Data Generator for End-to-End Pipeline Testing")
    print("="*80)
    
    # ============================================================================
    # Configuration
    # ============================================================================
    
    # Output directory structure (mirrors S3 structure)
    OUTPUT_BASE = Path("data/samples")
    
    # Sampling configuration
    AIRLINE_SAMPLE_RATIO = 0.001  # 0.1% of airline data
    WEATHER_SAMPLE_RATIO = 0.1  # 10% of weather data
    
    # ============================================================================
    # Data Source Paths
    # ============================================================================
    
    DATA_CONFIG = {
        # Main airline dataset
        "airline": {
            "input": "data/airline.csv.shuffle",
            "output": OUTPUT_BASE / "historical" / "airline_sample.csv",
            "sample_ratio": AIRLINE_SAMPLE_RATIO,
            "description": "Main airline flight data"
        },
        
        # Weather data (multiple files)
        "weather": {
            "input_files": [
                "preprocessing/weather_data_list1.csv",
                "preprocessing/weather_data_list2.csv",
                "preprocessing/weather_data_list3.csv",
                "preprocessing/weather_data_list4.csv",
                "preprocessing/weather_data_list5.csv",
            ],
            "output_dir": OUTPUT_BASE / "supplemental" / "weather",
            "sample_ratio": WEATHER_SAMPLE_RATIO,
            "combine": True,  # Combine into one file
            "description": "Weather observation data"
        },
        
        # Federal holidays (small file - copy entirely)
        "federal_holidays": {
            "input": "datafiles/federal_holidays.csv",
            "output": OUTPUT_BASE / "scraped" / "holidays" / "federal_holidays.csv",
            "copy_entire": True,  # Small file, copy entirely
            "description": "Federal holidays reference data"
        },
        
        # US Terrorism data (small file - copy entirely)
        "us_terrorism": {
            "input": "datafiles/us_terrorism_1987_2008.csv",
            "output": OUTPUT_BASE / "supplemental" / "security" / "us_terrorism_sample.csv",
            "copy_entire": True,  # Small file, copy entirely
            "description": "US terrorism incidents data"
        },
        
        # Global terrorism data (if available)
        "global_terrorism": {
            "input": "datafiles/globalterrorism_raw.csv",
            "output": OUTPUT_BASE / "supplemental" / "security" / "globalterrorism_sample.csv",
            "sample_ratio": 0.1,  # 10% sample if large
            "description": "Global terrorism incidents data"
        },
    }
    
    # ============================================================================
    # Process All Data Sources
    # ============================================================================
    
    results = {}
    
    # 1. Process airline data
    print("\n" + "="*80)
    print("STEP 1: Processing Airline Data")
    print("="*80)
    airline_cfg = DATA_CONFIG["airline"]
    results["airline"] = create_sample(
        airline_cfg["input"],
        str(airline_cfg["output"]),
        sample_ratio=airline_cfg["sample_ratio"]
    )
    
    # 2. Process weather data
    print("\n" + "="*80)
    print("STEP 2: Processing Weather Data")
    print("="*80)
    weather_cfg = DATA_CONFIG["weather"]
    results["weather"] = sample_weather_data(
        weather_cfg["input_files"],
        weather_cfg["output_dir"],
        sample_ratio=weather_cfg["sample_ratio"],
        combine=weather_cfg["combine"]
    )
    
    # 3. Process federal holidays
    print("\n" + "="*80)
    print("STEP 3: Processing Federal Holidays")
    print("="*80)
    holidays_cfg = DATA_CONFIG["federal_holidays"]
    results["federal_holidays"] = create_sample(
        holidays_cfg["input"],
        str(holidays_cfg["output"]),
        skip_if_small=True,
        max_size_mb=10
    )
    
    # 4. Process US terrorism data
    print("\n" + "="*80)
    print("STEP 4: Processing US Terrorism Data")
    print("="*80)
    terrorism_cfg = DATA_CONFIG["us_terrorism"]
    results["us_terrorism"] = create_sample(
        terrorism_cfg["input"],
        str(terrorism_cfg["output"]),
        skip_if_small=True,
        max_size_mb=10
    )
    
    # 5. Process global terrorism data (if exists)
    print("\n" + "="*80)
    print("STEP 5: Processing Global Terrorism Data")
    print("="*80)
    global_terrorism_cfg = DATA_CONFIG["global_terrorism"]
    results["global_terrorism"] = create_sample(
        global_terrorism_cfg["input"],
        str(global_terrorism_cfg["output"]),
        sample_ratio=global_terrorism_cfg.get("sample_ratio"),
        skip_if_small=True,
        max_size_mb=10
    )
    
    # ============================================================================
    # Summary
    # ============================================================================
    
    print("\n" + "="*80)
    print("SUMMARY")
    print("="*80)
    
    for name, success in results.items():
        status = "✓ SUCCESS" if success else "✗ FAILED"
        print(f"{status}: {name}")
    
    total_success = sum(1 for s in results.values() if s)
    print(f"\nCompleted: {total_success}/{len(results)} data sources")
    
    # ============================================================================
    # Next Steps
    # ============================================================================
    
    print("\n" + "="*80)
    print("NEXT STEPS")
    print("="*80)
    print("\n1. Review the generated samples in: data/samples/")
    print("\n2. Upload sample data to S3 (replace YOUR-RAW-BUCKET with your bucket name):")
    print(f"\n   # Airline data")
    print(f"   aws s3 cp {OUTPUT_BASE}/historical/ s3://YOUR-RAW-BUCKET/historical/ --recursive")
    print(f"\n   # Weather data")
    print(f"   aws s3 cp {OUTPUT_BASE}/supplemental/weather/ s3://YOUR-RAW-BUCKET/supplemental/weather/ --recursive")
    print(f"\n   # Federal holidays")
    print(f"   aws s3 cp {OUTPUT_BASE}/scraped/holidays/ s3://YOUR-RAW-BUCKET/scraped/holidays/ --recursive")
    print(f"\n   # Security/terrorism data")
    print(f"   aws s3 cp {OUTPUT_BASE}/supplemental/security/ s3://YOUR-RAW-BUCKET/supplemental/security/ --recursive")
    print("\n3. Run your Glue job with the sample data")
    print("4. Once validated, switch back to the full dataset and increase timeout")
    print("\n" + "="*80)

