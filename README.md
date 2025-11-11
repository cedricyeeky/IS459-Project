# Flight Delays Data Pipeline

A production-ready AWS data pipeline built with Terraform that processes flight delay data through a medallion architecture (Raw → Silver → Gold) with comprehensive error handling via S3 Dead Letter Queue.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         FLIGHT DELAYS PIPELINE                          │
└─────────────────────────────────────────────────────────────────────────┘

┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Data Sources   │     │   Lambda Scraper │     │   EventBridge    │
│                  │     │   (Wikipedia)    │     │   Schedules      │
│ • Kaggle CSV     │────▶│                  │◀────│                  │
│ • FAA Data       │     │  Sat 11PM UTC    │     │ • Lambda: Sat    │
│ • Plane Data     │     └────────┬─────────┘     │ • Glue: Sun 1AM  │
└──────────────────┘              │               │ • Crawlers: 2AM  │
                                  ▼               └──────────────────┘
                         ┌─────────────────┐
                         │   S3 RAW Bucket │
                         │  /historical/   │
                         │  /supplemental/ │
                         │  /scraped/      │
                         └────────┬────────┘
                                  │
                                  ▼
                    ┌──────────────────────────┐
                    │  Glue Job 1: Cleaning    │
                    │  • Schema validation     │
                    │  • Null handling         │
                    │  • Deduplication         │
                    │  • Outlier detection     │
                    └──────────┬───────────────┘
                               │
                ┌──────────────┴──────────────┐
                ▼                             ▼
       ┌─────────────────┐          ┌─────────────────┐
       │ S3 SILVER Bucket│          │   S3 DLQ Bucket │
       │   (Parquet)     │          │  /cleaning_errors/
       └────────┬────────┘          │  /scraping_errors/
                │                   │  /feature_eng_errors/
                ▼                   └─────────┬───────┘
   ┌──────────────────────────┐              │
   │ Glue Job 2: Features     │              ▼
   │ • Delay rate metrics     │     ┌─────────────────┐
   │ • Rolling averages       │     │   SNS Alerts    │
   │ • Holiday impact         │     │  (Email notify) │
   │ • Event correlation      │     └─────────────────┘
   └──────────┬───────────────┘
              │
              ▼
     ┌─────────────────┐
     │ S3 GOLD Bucket  │
     │   (Parquet)     │
     │ Analysis-ready  │
     └────────┬────────┘
              │
              ▼
     ┌─────────────────┐
     │  Glue Crawlers  │
     │  (Catalog Data) │
     └─────────────────┘
```

## Features

- **Medallion Architecture**: Raw → Silver → Gold data layers
- **Automated Data Ingestion**: Lambda-based web scraping for supplemental data
- **Robust ETL**: AWS Glue jobs with comprehensive error handling
- **Dead Letter Queue**: S3-based DLQ for failed records and error diagnostics
- **Automated Scheduling**: EventBridge schedules for weekly pipeline execution
- **Data Catalog**: AWS Glue crawlers for automatic schema discovery
- **Monitoring**: SNS email alerts for pipeline failures
- **Actionable Gold Outputs**: Gold layer publishes flight-level features plus cascade-risk and traveler reliability scorecards
- **Infrastructure as Code**: 100% Terraform with modular design

## Prerequisites

Before deploying this pipeline, ensure you have:

1. **AWS Account** with appropriate permissions
2. **AWS CLI** (v2.x or later) configured with credentials
   ```bash
   aws configure
   ```
3. **Terraform** (v1.5.0 or later)
   ```bash
   terraform --version
   ```
4. **Python 3.11** (for local Lambda testing)
5. **Git** (for version control)

## Project Structure

```
terraform/
├── main.tf                 # Root module orchestration
├── variables.tf            # Input variable definitions
├── outputs.tf              # Output value definitions
├── terraform.tfvars        # Variable values (gitignored)
├── terraform.tfvars.example # Example configuration
├── modules/
│   ├── s3/                 # S3 buckets with lifecycle policies
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── iam/                # IAM roles and policies
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── lambda/             # Lambda scraper infrastructure
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── src/
│   │       ├── .gitkeep    # Placeholder for future implementation
│   │       └── requirements.txt
│   ├── glue/               # Glue jobs, crawlers, database
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── scripts/
│   │       ├── data_cleaning.py
│   │       └── feature_engineering.py
│   └── notifications/      # SNS and EventBridge
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
```

## Deployment Instructions

### Step 1: Clone and Configure

```bash
# Clone the repository
git clone <your-repo-url>
cd IS459-Project/terraform

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your settings
nano terraform.tfvars
```

**Important**: Update `alert_email` in `terraform.tfvars` with your actual email address.

### Step 2: Initialize Terraform

```bash
# Initialize Terraform (downloads providers and modules)
terraform init
```

### Step 3: Review the Plan

```bash
# Generate and review execution plan
terraform plan

# Save plan to file (optional)
terraform plan -out=tfplan
```

### Step 4: Deploy Infrastructure

```bash
# Apply the configuration
terraform apply

# Or apply saved plan
terraform apply tfplan
```

Type `yes` when prompted to confirm deployment.

### Step 5: Confirm SNS Subscription

After deployment, check your email for an SNS subscription confirmation from AWS. Click the confirmation link to receive DLQ alerts.

### Step 6: Verify Deployment

```bash
# View outputs
terraform output

# Test AWS resources
aws s3 ls | grep flight-delays
aws glue get-databases
aws lambda list-functions | grep wikipedia-scraper
```

## Post-Deployment Setup

### Option 1: Upload Sample Data for Testing (Recommended First)

For end-to-end pipeline testing with a small subset of data:

```bash
# Step 1: Generate sample data from project root
cd /path/to/IS459-Project
python create_sample_data.py

# This creates samples in data/samples/:
# - data/samples/historical/airline_sample.csv (~0.1% of full dataset)
# - data/samples/supplemental/weather/weather_data_sample.csv (~10% sample)
# - data/samples/scraped/holidays/federal_holidays.csv (full file)
# - data/samples/supplemental/security/us_terrorism_sample.csv (full file)
# - data/samples/supplemental/security/globalterrorism_sample.csv (~10% sample)

# Step 2: Get bucket name from Terraform outputs
cd terraform
RAW_BUCKET=$(terraform output -raw raw_bucket_name)

# Step 3: Upload all sample data
aws s3 cp ../data/samples/historical/ s3://${RAW_BUCKET}/historical/ --recursive
aws s3 cp ../data/samples/supplemental/weather/ s3://${RAW_BUCKET}/supplemental/weather/ --recursive
aws s3 cp ../data/samples/scraped/holidays/ s3://${RAW_BUCKET}/scraped/holidays/ --recursive
aws s3 cp ../data/samples/supplemental/security/ s3://${RAW_BUCKET}/supplemental/security/ --recursive

# Step 4: Verify uploads
aws s3 ls s3://${RAW_BUCKET}/ --recursive
```

### Option 2: Upload Full Production Data

For production deployment with complete datasets:

```bash
# Get bucket name from Terraform outputs
cd terraform
RAW_BUCKET=$(terraform output -raw raw_bucket_name)

# Upload historical flight delay data (12GB Kaggle CSV)
aws s3 cp flight_delays.csv s3://${RAW_BUCKET}/historical/ --recursive

# Upload supplemental data (plane data, FAA enplanements)
aws s3 cp plane_data.csv s3://${RAW_BUCKET}/supplemental/
aws s3 cp faa_enplanements.csv s3://${RAW_BUCKET}/supplemental/

# Upload weather data
aws s3 cp preprocessing/weather_data_list*.csv s3://${RAW_BUCKET}/supplemental/weather/ --recursive

# Upload terrorism data (optional)
aws s3 cp datafiles/us_terrorism_1987_2008.csv s3://${RAW_BUCKET}/supplemental/security/
aws s3 cp datafiles/globalterrorism_raw.csv s3://${RAW_BUCKET}/supplemental/security/

# Verify uploads
aws s3 ls s3://${RAW_BUCKET}/ --recursive
```

#### Local Data Source Map

If you are working from this repository clone, the following helper datasets live under the project root and can be uploaded directly to S3 using the listed prefixes:

- `datafiles/plane-data.xls` → `s3://<raw-bucket>/supplemental/plane-data/`
- `datafiles/carriers.xls` → `s3://<raw-bucket>/supplemental/carriers/`
- `datafiles/airports.xls` → `s3://<raw-bucket>/supplemental/airports/`
- `datafiles/federal_holidays.csv` → `s3://<raw-bucket>/scraped/holidays/`
- `datafiles/globalterrorism_raw.csv`, `datafiles/us_terrorism_1987_2008.csv` → optional enrichment in `s3://<raw-bucket>/supplemental/security/`
- `preprocessing/weather_data_list*.csv` → `s3://<raw-bucket>/supplemental/weather/` (ingested by Glue Job 1; each file deduplicates on `obs_id`, `valid_time_gmt`)

> Tip: keep file names consistent when uploading so Glue Job 1 can infer schemas and preserve data lineage metadata.

### Manual Trigger Options

#### Trigger Lambda Scraper Manually

```bash
# Get Lambda function name from Terraform
cd terraform
LAMBDA_NAME=$(terraform output -raw lambda_function_name)

# Invoke Lambda function
aws lambda invoke \
  --function-name ${LAMBDA_NAME} \
  --invocation-type RequestResponse \
  --log-type Tail \
  response.json

# View response
cat response.json
```

#### Trigger Glue Workflow Manually

```bash
# Get workflow name from Terraform
cd terraform
WORKFLOW_NAME=$(terraform output -raw glue_workflow_name)

# Start the workflow (chains Job 1 → Job 2 automatically)
aws glue start-workflow-run --name ${WORKFLOW_NAME}

# Get run ID and check workflow status
RUN_ID=<run-id-from-previous-command>
aws glue get-workflow-run \
  --name ${WORKFLOW_NAME} \
  --run-id ${RUN_ID}
```

#### Trigger Individual Glue Jobs

```bash
# Get job names from Terraform
cd terraform
CLEANING_JOB=$(terraform output -raw cleaning_job_name)
FEATURE_JOB=$(terraform output -raw feature_job_name)

# Start data cleaning job
aws glue start-job-run --job-name ${CLEANING_JOB}

# Wait for completion, then start feature engineering job
aws glue start-job-run --job-name ${FEATURE_JOB}

# Check job status
aws glue get-job-runs \
  --job-name ${CLEANING_JOB} \
  --max-results 1 \
  --query 'JobRuns[0].{State:JobRunState,Id:Id}'
```

#### Trigger Glue Crawlers Manually

```bash
# Get crawler names from Terraform
cd terraform
RAW_CRAWLER=$(terraform output -raw raw_crawler_name)
SILVER_CRAWLER=$(terraform output -raw silver_crawler_name)
GOLD_CRAWLER=$(terraform output -raw gold_crawler_name)

# Start all crawlers
aws glue start-crawler --name ${RAW_CRAWLER}
aws glue start-crawler --name ${SILVER_CRAWLER}
aws glue start-crawler --name ${GOLD_CRAWLER}

# Check crawler status
aws glue get-crawler --name ${GOLD_CRAWLER} --query 'Crawler.{State:State,LastCrawl:LastCrawl}'
```

### Inspect Gold Outputs

Glue Job 2 publishes five datasets that directly address the business questions:

- `s3://<gold-bucket>/flight_features/` — flight-level records with rolling delays, holiday flags, cascade indicators, and reliability scores.
- `s3://<gold-bucket>/cascade_metrics/` — carrier/route aggregates exposing cascade triggers, propagation ratios, and arrival delay rates for airline operations.
- `s3://<gold-bucket>/reliability_metrics/` — traveler-facing scorecards combining on-time rates, cancellation risk, and percentile delays by flight hour.
- `s3://<gold-bucket>/weather_features/` — weather data with severity scores and impact categories (separate table for flexible joins).
- `s3://<gold-bucket>/terrorism_features/` — terrorism event data with severity categories and impact scores (separate table for flexible joins).

Validate a run by sampling the partitions:

```bash
# Get bucket name from Terraform
cd terraform
GOLD_BUCKET=$(terraform output -raw gold_bucket_name)

# Check all Gold layer outputs
aws s3 ls s3://${GOLD_BUCKET}/flight_features/ --recursive | head -5
aws s3 ls s3://${GOLD_BUCKET}/cascade_metrics/ --recursive | head -5
aws s3 ls s3://${GOLD_BUCKET}/reliability_metrics/ --recursive | head -5
aws s3 ls s3://${GOLD_BUCKET}/weather_features/ --recursive | head -5
aws s3 ls s3://${GOLD_BUCKET}/terrorism_features/ --recursive | head -5
```

Each aggregate includes a `snapshot_ts` column for freshness filtering and aligns to:

- **Business Question 1** — monitor `cascade_rate`, `cascade_propagation_ratio`, and `arrival_delay_rate` to minimize cascading delays.
- **Business Question 2** — surface `on_time_rate`, `cancellation_rate`, and `reliability_band` for traveler-facing reliability guidance.

**Note**: Weather and terrorism data are kept as separate tables in Gold layer for flexible querying. They are joined with flight data in Athena queries when needed for analysis.

### Set Up Real-Time Data Tables (For Analysis Queries)

The Athena analysis queries integrate real-time flight and weather data from your mock API. To use these queries, you need to set up the real-time data tables in Glue Catalog:

```bash
# See detailed setup instructions in:
cat terraform/modules/athena/REALTIME_DATA_SETUP.md

# Quick setup summary:
# 1. Create realtime_flights table pointing to your mock API data location
# 2. Create realtime_weather table pointing to your mock API weather data
# 3. Run Glue Crawlers to discover the tables, or create them manually in Athena
# 4. The Athena queries will automatically use real-time data when available
```

**Note**: The analysis queries work with historical data alone, but real-time data enhances the analysis with current conditions. See `terraform/modules/athena/REALTIME_DATA_SETUP.md` for complete setup instructions.

## Monitoring and Operations

### Monitor DLQ for Failures

The S3 DLQ bucket is the **primary monitoring mechanism** for pipeline failures.

```bash
# List all errors
aws s3 ls s3://flight-delays-dev-dlq/ --recursive

# Check scraping errors
aws s3 ls s3://flight-delays-dev-dlq/scraping_errors/ --recursive

# Check cleaning errors
aws s3 ls s3://flight-delays-dev-dlq/cleaning_errors/ --recursive

# Check feature engineering errors
aws s3 ls s3://flight-delays-dev-dlq/feature_eng_errors/ --recursive

# Download error file for analysis
aws s3 cp s3://flight-delays-dev-dlq/cleaning_errors/2024/11/04/12/part-00000.parquet ./
```

### View CloudWatch Logs

```bash
# Lambda logs
aws logs tail /aws/lambda/flight-delays-dev-wikipedia-scraper --follow

# Glue job logs
aws logs tail /aws-glue/jobs/output --follow

# Filter for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/flight-delays-dev-wikipedia-scraper \
  --filter-pattern "ERROR"
```

### Check Pipeline Status

```bash
# Check EventBridge schedules
aws events list-rules --name-prefix flight-delays

# Check Lambda last execution
aws lambda get-function --function-name flight-delays-dev-wikipedia-scraper

# Check Glue job runs
aws glue get-job-runs --job-name flight-delays-dev-data-cleaning --max-results 5
```

## Reprocessing Failed Records

### Step 1: Analyze DLQ Errors

```bash
# Download error files
aws s3 cp s3://flight-delays-dev-dlq/cleaning_errors/ ./errors/ --recursive

# Use PySpark or Pandas to analyze
python analyze_errors.py
```

### Step 2: Fix Source Data or Code

- If data quality issue: Clean and re-upload to Raw bucket
- If code issue: Update Glue script and redeploy

### Step 3: Rerun Pipeline

```bash
# Clear Silver/Gold buckets (optional, for full reprocess)
aws s3 rm s3://flight-delays-dev-silver/ --recursive
aws s3 rm s3://flight-delays-dev-gold/ --recursive

# Trigger workflow
aws glue start-workflow-run --name flight-delays-dev-workflow
```

### Step 4: Archive DLQ Errors

```bash
# Move processed errors to archive
aws s3 mv s3://flight-delays-dev-dlq/cleaning_errors/ \
  s3://flight-delays-dev-dlq/archive/cleaning_errors/ --recursive
```

## Testing Instructions

### End-to-End Pipeline Testing with Sample Data

This section provides comprehensive testing instructions for validating your entire pipeline with small sample datasets.

#### Step 1: Generate Sample Data

```bash
# From project root directory
cd /path/to/IS459-Project
python create_sample_data.py

# This creates small samples of all datasets:
# - Airline data: ~0.1% sample (reduces 12GB to ~12MB for testing)
# - Weather data: ~10% sample (reduces 3GB+ to ~300MB)
# - Holidays & terrorism: Full files (already small)
#
# Output location: data/samples/
```

#### Step 2: Upload Sample Data to S3

```bash
# Navigate to terraform directory
cd terraform

# Get bucket name from Terraform outputs
RAW_BUCKET=$(terraform output -raw raw_bucket_name)

# Upload all sample data
aws s3 cp ../data/samples/historical/ s3://${RAW_BUCKET}/historical/ --recursive
aws s3 cp ../data/samples/supplemental/weather/ s3://${RAW_BUCKET}/supplemental/weather/ --recursive
aws s3 cp ../data/samples/scraped/holidays/ s3://${RAW_BUCKET}/scraped/holidays/ --recursive
aws s3 cp ../data/samples/supplemental/security/ s3://${RAW_BUCKET}/supplemental/security/ --recursive

# Verify uploads
aws s3 ls s3://${RAW_BUCKET}/ --recursive
```

#### Step 3: Run Full Pipeline Workflow

```bash
# Get workflow name from Terraform
WORKFLOW_NAME=$(terraform output -raw glue_workflow_name)

# Run the complete workflow (Job 1 → Job 2 automatically)
aws glue start-workflow-run --name ${WORKFLOW_NAME}

# Get the run ID from output, then monitor progress
RUN_ID=<run-id-from-previous-command>
aws glue get-workflow-run \
  --name ${WORKFLOW_NAME} \
  --run-id ${RUN_ID}

# Check individual job status
aws glue get-job-runs \
  --job-name $(terraform output -raw cleaning_job_name) \
  --max-results 1
```

#### Step 4: Run Glue Crawlers

```bash
# Get crawler names from Terraform
RAW_CRAWLER=$(terraform output -raw raw_crawler_name)
SILVER_CRAWLER=$(terraform output -raw silver_crawler_name)
GOLD_CRAWLER=$(terraform output -raw gold_crawler_name)

# Start all crawlers to discover tables in Glue Catalog
aws glue start-crawler --name ${RAW_CRAWLER}
aws glue start-crawler --name ${SILVER_CRAWLER}
aws glue start-crawler --name ${GOLD_CRAWLER}

# Wait for completion (check status)
aws glue get-crawler --name ${GOLD_CRAWLER} --query 'Crawler.State'

# Verify tables were created
DB_NAME=$(terraform output -raw glue_database_name)
aws glue get-tables --database-name ${DB_NAME}
```

#### Step 5: Validate Gold Layer Outputs

```bash
# Get Gold bucket name
GOLD_BUCKET=$(terraform output -raw gold_bucket_name)

# Check all expected Gold tables exist
echo "=== Flight Features ==="
aws s3 ls s3://${GOLD_BUCKET}/flight_features/ --recursive | head -5

echo "=== Cascade Metrics ==="
aws s3 ls s3://${GOLD_BUCKET}/cascade_metrics/ --recursive | head -5

echo "=== Reliability Metrics ==="
aws s3 ls s3://${GOLD_BUCKET}/reliability_metrics/ --recursive | head -5

echo "=== Weather Features ==="
aws s3 ls s3://${GOLD_BUCKET}/weather_features/ --recursive | head -5

echo "=== Terrorism Features ==="
aws s3 ls s3://${GOLD_BUCKET}/terrorism_features/ --recursive | head -5
```

#### Step 6: Test Athena Queries

```bash
# Get database and workgroup names
DB_NAME=$(terraform output -raw glue_database_name)
WORKGROUP=$(terraform output -raw athena_workgroup_name)
RESULT_BUCKET=$(terraform output -raw raw_bucket_name)

# Test a simple query first
aws athena start-query-execution \
  --query-string "SELECT COUNT(*) as total_flights FROM ${DB_NAME}.flight_features LIMIT 10" \
  --work-group ${WORKGROUP} \
  --result-configuration OutputLocation=s3://${RESULT_BUCKET}/athena-results/

# Get query execution ID and check results
QUERY_EXECUTION_ID=<id-from-previous-command>
aws athena get-query-execution --query-execution-id ${QUERY_EXECUTION_ID}

# Access saved named queries via:
# 1. Athena Console → Saved queries tab
# 2. Or get query IDs from Terraform outputs:
terraform output athena_named_queries
```

#### Step 7: Check for Errors

```bash
# Check DLQ for any processing errors
DLQ_BUCKET=$(terraform output -raw dlq_bucket_name)
aws s3 ls s3://${DLQ_BUCKET}/ --recursive

# Check Glue job logs for warnings/errors
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs/output \
  --filter-pattern "ERROR" \
  --max-items 10

# Check for SNS email alerts (if errors occurred)
```

### Quick Testing Checklist

Use this checklist to verify your end-to-end pipeline:

```bash
# 1. Infrastructure deployed
terraform output

# 2. Sample data generated
ls -lh data/samples/historical/airline_sample.csv
ls -lh data/samples/supplemental/weather/weather_data_sample.csv

# 3. Data uploaded to S3
RAW_BUCKET=$(terraform -chdir=terraform output -raw raw_bucket_name)
aws s3 ls s3://${RAW_BUCKET}/historical/
aws s3 ls s3://${RAW_BUCKET}/supplemental/

# 4. Glue jobs completed successfully
CLEANING_JOB=$(terraform -chdir=terraform output -raw cleaning_job_name)
aws glue get-job-runs --job-name ${CLEANING_JOB} --max-results 1 \
  --query 'JobRuns[0].JobRunState'

# 5. Gold layer populated
GOLD_BUCKET=$(terraform -chdir=terraform output -raw gold_bucket_name)
aws s3 ls s3://${GOLD_BUCKET}/flight_features/ --recursive | head -5
aws s3 ls s3://${GOLD_BUCKET}/weather_features/ --recursive | head -5

# 6. Glue tables created
DB_NAME=$(terraform -chdir=terraform output -raw glue_database_name)
aws glue get-tables --database-name ${DB_NAME} --query 'TableList[].Name'

# 7. Athena queries accessible
terraform -chdir=terraform output athena_named_queries
```

### Test Lambda Locally (Optional)

```bash
cd terraform/modules/lambda/src

# Install dependencies
pip install -r requirements.txt

# Create test event
cat > test_event.json << EOF
{
  "test": true
}
EOF

# Run locally (after implementing scraper.py)
python scraper.py
```

### Simulate Failures for DLQ Testing

```bash
# Get bucket name
RAW_BUCKET=$(terraform -chdir=terraform output -raw raw_bucket_name)

# Upload malformed CSV to trigger schema validation errors
echo "invalid,data,format" > bad_data.csv
aws s3 cp bad_data.csv s3://${RAW_BUCKET}/historical/

# Trigger cleaning job
CLEANING_JOB=$(terraform -chdir=terraform output -raw cleaning_job_name)
aws glue start-job-run --job-name ${CLEANING_JOB}

# Verify error in DLQ
DLQ_BUCKET=$(terraform -chdir=terraform output -raw dlq_bucket_name)
aws s3 ls s3://${DLQ_BUCKET}/cleaning_errors/ --recursive

# Check for SNS email alert
```

## Cost Estimation

Estimated monthly costs for **dev environment** with moderate usage:

| Service | Usage | Monthly Cost |
|---------|-------|--------------|
| S3 Storage | 50 GB (Raw + Silver + Gold) | $1.15 |
| S3 Requests | 100K PUT, 500K GET | $0.50 |
| Lambda | 4 invocations/month, 512MB, 5min | $0.01 |
| Glue Jobs | 8 runs/month, 2 workers, 30min avg | $8.00 |
| Glue Crawlers | 12 runs/month, 5min avg | $0.44 |
| Glue Data Catalog | 1 database, 3 tables | $1.00 |
| SNS | 100 notifications/month | $0.01 |
| EventBridge | 12 schedule invocations | $0.00 |
| CloudWatch Logs | 5 GB ingestion, 1 month retention | $2.50 |
| **Total** | | **~$13.61/month** |

**Production environment** costs will be higher based on:
- Data volume (12GB+ historical data)
- Processing frequency (daily vs weekly)
- Data retention policies
- Number of Glue workers

### Cost Optimization Tips

1. **Adjust lifecycle policies**: Transition to Glacier for long-term storage
2. **Reduce Glue workers**: Use 1 worker for small datasets
3. **Optimize schedules**: Run less frequently if real-time not needed
4. **Enable S3 Intelligent-Tiering**: Automatic cost optimization
5. **Set CloudWatch log retention**: Reduce from 14 to 7 days

## Configuration Variables

Key variables in `terraform.tfvars`:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `alert_email` | Email for DLQ alerts | - | **Yes** |
| `lambda_memory_size` | Lambda memory in MB | `512` | No |
| `lambda_timeout` | Lambda timeout in seconds | `300` | No |
| `cleaning_worker_count` | Glue workers for cleaning job | `2` | No |
| `feature_worker_count` | Glue workers for feature job | `2` | No |
| `scraping_schedule` | Cron for Lambda scraper | `cron(0 23 ? * SAT *)` | No |
| `cleaning_schedule` | Cron for Glue cleaning | `cron(0 1 ? * SUN *)` | No |

## Troubleshooting

### Issue: Terraform apply fails with "bucket already exists"

**Solution**: S3 bucket names must be globally unique. Change `resource_prefix` in `terraform.tfvars`:
```hcl
resource_prefix = "flight-delays-yourname"
```

### Issue: Lambda function has no code

**Expected**: Lambda implementation scripts are intentionally not included. The infrastructure is ready for future implementation in `terraform/modules/lambda/src/`.

### Issue: Glue job fails with "Access Denied" to S3

**Solution**: 
1. Check IAM role permissions: `terraform/modules/iam/main.tf`
2. Verify bucket policies allow Glue service role
3. Ensure S3 buckets exist before running jobs

### Issue: SNS email not received

**Solution**:
1. Check spam folder
2. Verify email in `terraform.tfvars`
3. Confirm subscription in AWS Console: SNS → Subscriptions
4. Manually confirm subscription

### Issue: Glue job timeout

**Solution**: Increase timeout in `terraform.tfvars`:
```hcl
cleaning_timeout = 60  # Increase from 30 to 60 minutes
```

### Issue: DLQ bucket filling up

**Solution**: 
1. Investigate root cause of errors
2. Fix data quality or code issues
3. Reprocess successfully
4. Archive old errors:
```bash
aws s3 mv s3://flight-delays-dev-dlq/ s3://flight-delays-archive-dlq/ --recursive
```

## Maintenance

### Update Glue Scripts

```bash
# Edit scripts locally
nano terraform/modules/glue/scripts/data_cleaning.py

# Apply changes (Terraform will upload new version)
terraform apply

# Verify update
aws s3 ls s3://flight-delays-dev-raw/glue-scripts/
```

### Update Lambda Configuration

```bash
# Edit variables
nano terraform.tfvars

# Apply changes
terraform apply

# Verify
aws lambda get-function-configuration \
  --function-name flight-delays-dev-wikipedia-scraper
```

### Rotate IAM Credentials

```bash
# Update IAM policies
nano terraform/modules/iam/main.tf

# Apply changes
terraform apply
```

### Backup Terraform State

```bash
# Enable S3 backend (uncomment in main.tf)
# Create state bucket
aws s3 mb s3://your-terraform-state-bucket

# Migrate state
terraform init -migrate-state
```

## Cleanup

To completely destroy all resources and avoid ongoing charges, follow these comprehensive cleanup steps:

### Step 1: Stop All Scheduled Jobs

First, disable all EventBridge schedules to prevent new executions during cleanup:

```bash
# Get schedule names from Terraform outputs (if available)
# Or use AWS Console to find schedule names

# Disable Lambda scraper schedule
aws events disable-rule --name flight-delays-dev-lambda-schedule

# Disable Glue workflow schedule
aws events disable-rule --name flight-delays-dev-cleaning-schedule

# Disable crawler schedules (EventBridge Scheduler)
# Note: Schedule names may vary - check AWS Console or Terraform outputs
aws scheduler update-schedule \
  --name flight-delays-dev-raw-crawler-schedule \
  --state DISABLED \
  --flexible-time-window Mode=OFF \
  --schedule-expression "cron(0 2 ? * SUN *)" || echo "Schedule not found"

aws scheduler update-schedule \
  --name flight-delays-dev-silver-crawler-schedule \
  --state DISABLED \
  --flexible-time-window Mode=OFF \
  --schedule-expression "cron(0 2 ? * SUN *)" || echo "Schedule not found"

aws scheduler update-schedule \
  --name flight-delays-dev-gold-crawler-schedule \
  --state DISABLED \
  --flexible-time-window Mode=OFF \
  --schedule-expression "cron(0 2 ? * SUN *)" || echo "Schedule not found"
```

### Step 2: Stop Running Jobs

Check for and stop any currently running jobs:

```bash
# Get job names from Terraform
cd terraform
CLEANING_JOB=$(terraform output -raw cleaning_job_name)
FEATURE_JOB=$(terraform output -raw feature_job_name)

# Check running Glue jobs
aws glue get-job-runs \
  --job-name ${CLEANING_JOB} \
  --max-results 5

aws glue get-job-runs \
  --job-name ${FEATURE_JOB} \
  --max-results 5

# Stop running jobs if any (replace <run-id> with actual run ID)
# aws glue batch-stop-job-run \
#   --job-name ${CLEANING_JOB} \
#   --job-run-ids <run-id>

# Get crawler names from Terraform
RAW_CRAWLER=$(terraform output -raw raw_crawler_name)
SILVER_CRAWLER=$(terraform output -raw silver_crawler_name)
GOLD_CRAWLER=$(terraform output -raw gold_crawler_name)

# Check running crawlers
aws glue get-crawler --name ${RAW_CRAWLER}
aws glue get-crawler --name ${SILVER_CRAWLER}
aws glue get-crawler --name ${GOLD_CRAWLER}

# Stop running crawlers if any
# aws glue stop-crawler --name ${RAW_CRAWLER}
# aws glue stop-crawler --name ${SILVER_CRAWLER}
# aws glue stop-crawler --name ${GOLD_CRAWLER}
```

### Step 3: Clean Up Glue Catalog Tables

Glue crawlers create catalog tables that are not managed by Terraform and must be manually deleted:

```bash
# Get database name from Terraform
cd terraform
DB_NAME=$(terraform output -raw glue_database_name)

# List all tables in the database
aws glue get-tables --database-name ${DB_NAME}

# Delete all tables (crawlers create these during execution)
# Note: Table names will vary based on your data structure
# Common patterns: historical, supplemental, scraped, silver_data, gold_data, 
#                  flight_features, cascade_metrics, reliability_metrics, 
#                  weather_features, terrorism_features

# Get all table names and delete them
for table in $(aws glue get-tables --database-name ${DB_NAME} --query 'TableList[].Name' --output text); do
  echo "Deleting table: $table"
  aws glue delete-table --database-name ${DB_NAME} --name $table
done
```

### Step 4: Clean Up Glue Job Metadata

Remove job run history and bookmarks:

```bash
# Get job names from Terraform
cd terraform
CLEANING_JOB=$(terraform output -raw cleaning_job_name)
FEATURE_JOB=$(terraform output -raw feature_job_name)

# Delete job bookmarks (if you want to start fresh)
aws glue reset-job-bookmark --job-name ${CLEANING_JOB}
aws glue reset-job-bookmark --job-name ${FEATURE_JOB}

# Note: Job run history is automatically cleaned up when jobs are deleted by Terraform
```

### Step 5: Empty S3 Buckets

S3 buckets with data cannot be destroyed by Terraform. Empty them first:

```bash
# Get bucket names from Terraform
cd terraform
RAW_BUCKET=$(terraform output -raw raw_bucket_name)
SILVER_BUCKET=$(terraform output -raw silver_bucket_name)
GOLD_BUCKET=$(terraform output -raw gold_bucket_name)
DLQ_BUCKET=$(terraform output -raw dlq_bucket_name)

# Empty buckets
aws s3 rm s3://${RAW_BUCKET}/ --recursive
aws s3 rm s3://${SILVER_BUCKET}/ --recursive
aws s3 rm s3://${GOLD_BUCKET}/ --recursive
aws s3 rm s3://${DLQ_BUCKET}/ --recursive

# Verify all buckets are empty
aws s3 ls s3://${RAW_BUCKET}/ --recursive
aws s3 ls s3://${SILVER_BUCKET}/ --recursive
aws s3 ls s3://${GOLD_BUCKET}/ --recursive
aws s3 ls s3://${DLQ_BUCKET}/ --recursive
```

**Note**: If the raw bucket has more than 1000 versions, repeat the delete commands until `list-object-versions` returns no Versions or DeleteMarkers.

### Step 6: Delete CloudWatch Log Streams

CloudWatch log streams accumulate over time and may not be fully cleaned by Terraform:

```bash
# Get Lambda function name from Terraform
cd terraform
LAMBDA_NAME=$(terraform output -raw lambda_function_name)

# Delete Lambda log streams
aws logs delete-log-group --log-group-name /aws/lambda/${LAMBDA_NAME} || true

# Delete Glue job log streams
# Note: Glue creates dynamic log groups like /aws-glue/jobs/output, /aws-glue/jobs/error
# List and delete them manually
aws logs describe-log-groups --log-group-name-prefix /aws-glue/jobs

# Delete specific Glue log groups if they exist
aws logs delete-log-group --log-group-name /aws-glue/jobs/output || true
aws logs delete-log-group --log-group-name /aws-glue/jobs/error || true
aws logs delete-log-group --log-group-name /aws-glue/jobs/logs-v2 || true

# Delete Spark UI event logs stored in S3 (already handled in Step 5)
# These are in s3://<raw-bucket>/glue-logs/
```

### Step 7: Run Terraform Destroy

Now destroy all Terraform-managed infrastructure:

```bash
# Review resources to be destroyed
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Type 'yes' when prompted
```

### Step 8: Verify Complete Cleanup

Verify all resources have been removed:

```bash
# Get resource prefix from Terraform (if still available)
cd terraform
RESOURCE_PREFIX=$(terraform output -raw deployment_summary | jq -r '.resource_prefix' || echo "flight-delays-dev")

# Check S3 buckets
aws s3 ls | grep ${RESOURCE_PREFIX}

# Check Lambda functions
aws lambda list-functions | grep ${RESOURCE_PREFIX}

# Check Glue resources
aws glue get-databases | grep ${RESOURCE_PREFIX}
aws glue list-jobs | grep ${RESOURCE_PREFIX}
aws glue list-crawlers | grep ${RESOURCE_PREFIX}
aws glue list-workflows | grep ${RESOURCE_PREFIX}

# Check EventBridge rules
aws events list-rules --name-prefix ${RESOURCE_PREFIX}
aws scheduler list-schedules | grep ${RESOURCE_PREFIX}

# Check SNS topics
aws sns list-topics | grep ${RESOURCE_PREFIX}

# Check IAM roles
aws iam list-roles | grep ${RESOURCE_PREFIX}

# Check CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/${RESOURCE_PREFIX}
aws logs describe-log-groups --log-group-name-prefix /aws-glue
```

### Step 9: Manual Cleanup of Persistent Resources (if needed)

If any resources remain after Terraform destroy:

```bash
# Get resource names from Terraform outputs (if still available)
cd terraform
RAW_BUCKET=$(terraform output -raw raw_bucket_name 2>/dev/null || echo "flight-delays-dev-raw")
SILVER_BUCKET=$(terraform output -raw silver_bucket_name 2>/dev/null || echo "flight-delays-dev-silver")
GOLD_BUCKET=$(terraform output -raw gold_bucket_name 2>/dev/null || echo "flight-delays-dev-gold")
DLQ_BUCKET=$(terraform output -raw dlq_bucket_name 2>/dev/null || echo "flight-delays-dev-dlq")
DB_NAME=$(terraform output -raw glue_database_name 2>/dev/null || echo "flight-delays-dev-db")

# Force delete S3 buckets if they still exist
aws s3 rb s3://${RAW_BUCKET} --force || true
aws s3 rb s3://${SILVER_BUCKET} --force || true
aws s3 rb s3://${GOLD_BUCKET} --force || true
aws s3 rb s3://${DLQ_BUCKET} --force || true

# Delete EventBridge Scheduler schedules if they persist
aws scheduler delete-schedule --name ${RAW_BUCKET}-raw-crawler-schedule || true
aws scheduler delete-schedule --name ${RAW_BUCKET}-silver-crawler-schedule || true
aws scheduler delete-schedule --name ${RAW_BUCKET}-gold-crawler-schedule || true

# Delete Glue database if it persists
aws glue delete-database --name ${DB_NAME} || true

# Delete SNS subscriptions manually (check email for unsubscribe link)
# Or use AWS Console: SNS → Subscriptions → Delete
```

### Cleanup Checklist

Use this checklist to ensure complete cleanup:

- [ ] All EventBridge schedules disabled
- [ ] No Glue jobs currently running
- [ ] No crawlers currently running
- [ ] All Glue catalog tables deleted
- [ ] All S3 buckets emptied
- [ ] CloudWatch log groups deleted
- [ ] `terraform destroy` completed successfully
- [ ] No S3 buckets remain
- [ ] No Lambda functions remain
- [ ] No Glue databases remain
- [ ] No Glue jobs remain
- [ ] No Glue crawlers remain
- [ ] No Glue workflows remain
- [ ] No EventBridge rules remain
- [ ] No EventBridge Scheduler schedules remain
- [ ] No SNS topics remain
- [ ] No IAM roles remain (flight-delays-*)
- [ ] No CloudWatch log groups remain

### Cost-Saving Partial Cleanup

If you want to pause the pipeline without full deletion:

```bash
# Get resource names from Terraform
cd terraform
RAW_BUCKET=$(terraform output -raw raw_bucket_name)
SILVER_BUCKET=$(terraform output -raw silver_bucket_name)
GOLD_BUCKET=$(terraform output -raw gold_bucket_name)
DLQ_BUCKET=$(terraform output -raw dlq_bucket_name)

# Disable schedules only (keeps infrastructure but stops execution)
# Note: Get actual schedule names from AWS Console or EventBridge
aws events disable-rule --name flight-delays-dev-lambda-schedule || echo "Rule not found"
aws events disable-rule --name flight-delays-dev-cleaning-schedule || echo "Rule not found"

# Empty large data buckets to save storage costs
aws s3 rm s3://${RAW_BUCKET}/historical/ --recursive
aws s3 rm s3://${SILVER_BUCKET}/ --recursive
aws s3 rm s3://${GOLD_BUCKET}/ --recursive

# Keep DLQ for analysis, but archive old errors
# aws s3 mv s3://${DLQ_BUCKET}/ s3://archive-bucket/dlq-backup/ --recursive
```

**Warning**: This cleanup process will **permanently delete all data and resources**. Ensure you have:
- Exported any important analysis results
- Backed up any data you need to retain
- Confirmed no downstream systems depend on this pipeline
- Documented any insights or configurations you want to preserve

## Security Best Practices

1. **Enable S3 bucket versioning**: Already enabled for Raw bucket
2. **Use KMS encryption**: Upgrade from SSE-S3 to SSE-KMS for sensitive data
3. **Restrict IAM permissions**: Follow least privilege (already implemented)
4. **Enable CloudTrail**: Audit all API calls
5. **Use VPC endpoints**: Reduce internet exposure for Glue jobs
6. **Rotate credentials**: Regularly update access keys
7. **Enable MFA**: For AWS Console access
8. **Review security groups**: If using VPC for Lambda

## Future Enhancements

- [ ] Implement Lambda scraper Python code (`scraper.py`)
- [ ] Add real-time streaming with Kinesis
- [ ] Integrate with QuickSight for dashboards
- [ ] Add data quality metrics to CloudWatch
- [ ] Implement data lineage tracking
- [ ] Add unit tests for Glue scripts
- [ ] Create CI/CD pipeline with GitHub Actions
- [x] Add Athena queries for Gold layer analysis (BQ1 & BQ2 queries implemented)
- [ ] Set up real-time data tables (realtime_flights, realtime_weather) in Glue Catalog
- [ ] Integrate with QuickSight for visualization dashboards
- [ ] Implement incremental processing with job bookmarks
- [ ] Add data validation with Great Expectations

## Support and Contributing

For issues, questions, or contributions:
1. Open an issue in the repository
2. Submit a pull request with improvements
3. Contact the maintainers

## License

[Your License Here]

## Acknowledgments

- AWS Glue documentation
- Terraform AWS provider documentation
- Flight delay data from Kaggle
- Wikipedia for supplemental data sources

---

**Built with ❤️ using Terraform and AWS**

