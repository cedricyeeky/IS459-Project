#!/usr/bin/env python3
"""
Script to create a sample subset of the large airline dataset for testing.
This will help test Glue jobs without processing the entire 12GB file.
"""

import csv
import sys
from pathlib import Path

def create_sample(input_file, output_file, num_rows=100000, sample_ratio=None):
    """
    Create a sample of the CSV file.
    
    Args:
        input_file: Path to the large CSV file
        output_file: Path to save the sample
        num_rows: Number of rows to extract (default: 100,000)
        sample_ratio: Alternative - sample every Nth row (e.g., 0.01 for 1%)
    """
    print(f"Creating sample from {input_file}")
    print(f"Target: {num_rows if not sample_ratio else f'{sample_ratio*100}%'} rows")
    
    input_path = Path(input_file)
    output_path = Path(output_file)
    
    if not input_path.exists():
        print(f"Error: Input file {input_file} does not exist")
        return False
    
    rows_written = 0
    rows_read = 0
    
    try:
        with open(input_path, 'r', encoding='utf-8', errors='replace') as infile, \
             open(output_path, 'w', encoding='utf-8', newline='') as outfile:
            
            # Read header
            header = infile.readline()
            outfile.write(header)
            print(f"Header: {header.strip()}")
            
            if sample_ratio:
                # Sample by ratio (e.g., every 100th row for 0.01)
                import random
                random.seed(42)  # For reproducibility
                
                for line in infile:
                    rows_read += 1
                    if random.random() < sample_ratio:
                        outfile.write(line)
                        rows_written += 1
                    
                    if rows_read % 1000000 == 0:
                        print(f"Processed {rows_read:,} rows, sampled {rows_written:,} rows...")
            else:
                # Sample first N rows
                for line in infile:
                    rows_read += 1
                    outfile.write(line)
                    rows_written += 1
                    
                    if rows_written >= num_rows:
                        break
                    
                    if rows_read % 100000 == 0:
                        print(f"Extracted {rows_written:,} rows...")
        
        print(f"\n✓ Sample created successfully!")
        print(f"  Total rows read: {rows_read:,}")
        print(f"  Rows in sample: {rows_written:,}")
        print(f"  Output file: {output_path}")
        print(f"  File size: {output_path.stat().st_size / (1024*1024):.2f} MB")
        return True
        
    except Exception as e:
        print(f"Error creating sample: {e}")
        return False

if __name__ == "__main__":
    # Configuration
    INPUT_FILE = "data/airline.csv.shuffle"
    OUTPUT_FILE = "data/airline_sample.csv"
    
    # Choose one approach:
    # Option 1: First 100K rows (fast, good for initial testing)
    # create_sample(INPUT_FILE, OUTPUT_FILE, num_rows=100000)
    
    # Option 2: First 500K rows (more data for better testing)
    # create_sample(INPUT_FILE, OUTPUT_FILE, num_rows=500000)
    
    # Option 3: 1% random sample (representative of full dataset)
    create_sample(INPUT_FILE, OUTPUT_FILE, sample_ratio=0.01)
    
    print("\nNext steps:")
    print("1. Upload the sample file to S3:")
    print(f"   aws s3 cp {OUTPUT_FILE} s3://YOUR-RAW-BUCKET/historical/")
    print("2. Run your Glue job with the sample data")
    print("3. Once validated, switch back to the full dataset and increase timeout")

