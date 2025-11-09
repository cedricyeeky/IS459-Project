# Testing Guide for Data Cleaning Updates

## ✅ Tests Already Passed

### Logic Validation Test
```bash
python3 test_logic_simple.py
```
**Status:** ✅ **PASSED** - All deduplication logic validated

---

## Testing Options

### Option 1: Simple Logic Test (NO DEPENDENCIES) ⚡ **FASTEST**
**What it tests:** Column detection and key filtering logic  
**Requires:** Nothing! Just Python 3  
**Time:** ~1 second

```bash
python3 test_logic_simple.py
```

✅ **Already validated and passed!**

---

### Option 2: Local PySpark Test (RECOMMENDED)
**What it tests:** Full deduplication with actual weather data  
**Requires:** PySpark installation  
**Time:** ~30 seconds

#### Setup:
```bash
pip install pyspark
```

#### Run:
```bash
python3 test_data_cleaning.py
```

#### What to expect:
```
TEST 1: Weather Data Deduplication
✅ Weather data test passed!

TEST 2: Flight Data Deduplication  
✅ Flight data test passed!

TEST 3: Missing Columns Handling
✅ Missing columns test passed!

TEST 4: All Columns Deduplication
✅ All columns deduplication test passed!

TEST 5: Supplemental Data Type Detection
✅ Auto-detection test passed!

✅ ALL TESTS PASSED!
```

---

### Option 3: AWS Glue Test (PRODUCTION VALIDATION)
**What it tests:** Actual AWS Glue job execution  
**Requires:** AWS credentials, Terraform deployed infrastructure  
**Time:** ~5-10 minutes

#### Step 1: Upload Sample Data
```bash
# Edit test_glue_weather.sh and update:
# - RAW_BUCKET="your-raw-bucket-name"
# - REGION="your-region"

./test_glue_weather.sh
```

#### Step 2: Trigger Glue Job
Either:
- **Manual:** Run Glue job from AWS Console
- **Automated:** Use Terraform or AWS CLI

```bash
aws glue start-job-run \
    --job-name your-data-cleaning-job \
    --region us-east-1
```

#### Step 3: Check CloudWatch Logs
Look for these messages in CloudWatch:
```
✅ "Detected weather data format"
✅ "Deduplicating using columns: ['obs_id', 'valid_time_gmt']"
✅ "Removed X duplicate records"
✅ "Supplemental data processing complete"
```

#### Step 4: Verify Output
```bash
# Check Silver bucket for processed data
aws s3 ls s3://your-silver-bucket/ --recursive

# Download and inspect
aws s3 cp s3://your-silver-bucket/data.parquet /tmp/ --recursive
```

---

## Test Scenarios Covered

| Scenario | Test Method | Status |
|----------|-------------|--------|
| Weather data column detection | Logic test | ✅ Passed |
| Weather deduplication keys | Logic test | ✅ Passed |
| Missing columns handling | Logic test | ✅ Passed |
| Flight data (shouldn't use weather keys) | Logic test | ✅ Passed |
| Actual weather CSV reading | PySpark test | ⏳ Pending |
| Full deduplication on real data | PySpark test | ⏳ Pending |
| AWS Glue execution | AWS test | ⏳ Pending |
| CloudWatch logging | AWS test | ⏳ Pending |

---

## What Each Test Validates

### ✅ Logic Test (Completed)
- Column detection works (`obs_id`, `valid_time_gmt`)
- Key filtering removes non-existent columns
- Doesn't false-positive on flight data

### ⏳ PySpark Test (Optional - Requires Setup)
- Reads actual CSV files correctly
- Deduplication removes duplicates
- Schema inference works
- All data types handled

### ⏳ AWS Glue Test (Required Before Production)
- S3 read/write operations
- Glue job execution
- Error handling and DLQ
- CloudWatch logging
- Performance at scale

---

## Quick Start Recommendation

**For immediate validation:**
```bash
# Already passed! ✅
python3 test_logic_simple.py
```

**Before deploying to AWS:**
```bash
# 1. Install PySpark (optional but recommended)
pip install pyspark

# 2. Run full local test
python3 test_data_cleaning.py

# 3. Deploy to AWS and run sample test
./test_glue_weather.sh
# Then trigger Glue job and check CloudWatch
```

---

## Troubleshooting

### If PySpark test fails:
```bash
# Check PySpark installation
python3 -c "import pyspark; print(pyspark.__version__)"

# If import fails, reinstall:
pip install --upgrade pyspark
```

### If AWS test fails:
- Check S3 bucket names in script
- Verify AWS credentials: `aws sts get-caller-identity`
- Check Glue job exists: `aws glue get-job --job-name <name>`
- Review CloudWatch logs for errors

---

## Expected Results

### Weather Data Processing:
- **Input:** 822,212 rows from `weather_data_list1.csv`
- **Columns:** `obs_id`, `valid_time_gmt`, `wx_phrase`, `temp`, etc.
- **Dedup Keys:** `obs_id`, `valid_time_gmt`
- **Output:** Deduplicated Parquet in Silver bucket

### Log Messages to Look For:
```
✅ "Read X records from supplemental CSV data"
✅ "Detected weather data format"  
✅ "Deduplicating using columns: ['obs_id', 'valid_time_gmt']"
✅ "Removed X duplicate records"
✅ "Supplemental data processing complete: Y records"
✅ "Successfully wrote Y records to Silver bucket"
```

### Red Flags 🚩:
```
❌ "None of the specified key columns ... exist in DataFrame"
❌ "KeyError: 'Year'" or similar
❌ "Error processing supplemental data"
```

If you see red flags, the code still has issues!

---

## Next Steps After Testing

1. ✅ Logic validation passed
2. ⏳ Run PySpark test (optional but recommended)
3. ⏳ Deploy updated `data_cleaning.py` to AWS
4. ⏳ Upload weather data to S3 raw bucket
5. ⏳ Run Glue job and monitor CloudWatch
6. ⏳ Verify output in Silver bucket
7. ✅ Production ready!
