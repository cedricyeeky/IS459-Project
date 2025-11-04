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

### Upload Initial Data to Raw Bucket

```bash
# Upload historical flight delay data (12GB Kaggle CSV)
aws s3 cp flight_delays.csv s3://flight-delays-dev-raw/historical/ --recursive

# Upload supplemental data (plane data, FAA enplanements)
aws s3 cp plane_data.csv s3://flight-delays-dev-raw/supplemental/
aws s3 cp faa_enplanements.csv s3://flight-delays-dev-raw/supplemental/

# Verify uploads
aws s3 ls s3://flight-delays-dev-raw/ --recursive
```

### Manual Trigger Options

#### Trigger Lambda Scraper Manually

```bash
# Invoke Lambda function
aws lambda invoke \
  --function-name flight-delays-dev-wikipedia-scraper \
  --invocation-type RequestResponse \
  --log-type Tail \
  response.json

# View response
cat response.json
```

#### Trigger Glue Workflow Manually

```bash
# Start the workflow (chains Job 1 → Job 2 automatically)
aws glue start-workflow-run --name flight-delays-dev-workflow

# Check workflow status
aws glue get-workflow-run \
  --name flight-delays-dev-workflow \
  --run-id <run-id-from-previous-command>
```

#### Trigger Individual Glue Jobs

```bash
# Start data cleaning job
aws glue start-job-run --job-name flight-delays-dev-data-cleaning

# Start feature engineering job (after cleaning completes)
aws glue start-job-run --job-name flight-delays-dev-feature-engineering

# Check job status
aws glue get-job-run \
  --job-name flight-delays-dev-data-cleaning \
  --run-id <run-id>
```

#### Trigger Glue Crawlers Manually

```bash
# Start all crawlers
aws glue start-crawler --name flight-delays-dev-raw-crawler
aws glue start-crawler --name flight-delays-dev-silver-crawler
aws glue start-crawler --name flight-delays-dev-gold-crawler

# Check crawler status
aws glue get-crawler --name flight-delays-dev-raw-crawler
```

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

### Test Lambda Locally

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

### Test Glue Jobs with Sample Data

```bash
# Create small sample dataset
head -n 1000 flight_delays.csv > sample_data.csv

# Upload to test bucket
aws s3 cp sample_data.csv s3://flight-delays-dev-raw/historical/test/

# Run Glue job with test data
aws glue start-job-run \
  --job-name flight-delays-dev-data-cleaning \
  --arguments '{"--RAW_BUCKET":"flight-delays-dev-raw/historical/test/"}'
```

### Simulate Failures for DLQ Testing

```bash
# Upload malformed CSV to trigger schema validation errors
echo "invalid,data,format" > bad_data.csv
aws s3 cp bad_data.csv s3://flight-delays-dev-raw/historical/

# Trigger cleaning job
aws glue start-job-run --job-name flight-delays-dev-data-cleaning

# Verify error in DLQ
aws s3 ls s3://flight-delays-dev-dlq/cleaning_errors/ --recursive

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

To destroy all resources:

```bash
# Review resources to be destroyed
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Manually delete S3 buckets if they contain data
aws s3 rb s3://flight-delays-dev-raw --force
aws s3 rb s3://flight-delays-dev-silver --force
aws s3 rb s3://flight-delays-dev-gold --force
aws s3 rb s3://flight-delays-dev-dlq --force
```

**Warning**: This will permanently delete all data and resources. Ensure you have backups if needed.

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
- [ ] Add Athena queries for Gold layer analysis
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

