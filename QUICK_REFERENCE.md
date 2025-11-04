# Flight Delays Pipeline - Quick Reference Guide

## 🚀 Deployment Commands

```bash
# Initial setup
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Edit alert_email

# Deploy
terraform init
terraform plan
terraform apply

# Destroy (cleanup)
terraform destroy
```

## 📤 Data Upload Commands

```bash
# Upload historical data
aws s3 cp flight_delays.csv s3://flight-delays-dev-raw/historical/

# Upload supplemental data
aws s3 cp plane_data.csv s3://flight-delays-dev-raw/supplemental/

# Upload in bulk
aws s3 sync ./data/ s3://flight-delays-dev-raw/historical/

# Verify uploads
aws s3 ls s3://flight-delays-dev-raw/ --recursive
```

## ▶️ Manual Trigger Commands

```bash
# Trigger Lambda scraper
aws lambda invoke \
  --function-name flight-delays-dev-wikipedia-scraper \
  --invocation-type RequestResponse \
  response.json

# Trigger Glue workflow (recommended)
aws glue start-workflow-run --name flight-delays-dev-workflow

# Trigger individual Glue jobs
aws glue start-job-run --job-name flight-delays-dev-data-cleaning
aws glue start-job-run --job-name flight-delays-dev-feature-engineering

# Trigger crawlers
aws glue start-crawler --name flight-delays-dev-raw-crawler
aws glue start-crawler --name flight-delays-dev-silver-crawler
aws glue start-crawler --name flight-delays-dev-gold-crawler
```

## 📊 Monitoring Commands

```bash
# Check DLQ for errors
aws s3 ls s3://flight-delays-dev-dlq/ --recursive

# View Lambda logs
aws logs tail /aws/lambda/flight-delays-dev-wikipedia-scraper --follow

# View Glue job logs
aws logs tail /aws-glue/jobs/output --follow

# Check job status
aws glue get-job-run \
  --job-name flight-delays-dev-data-cleaning \
  --run-id <run-id>

# Check workflow status
aws glue get-workflow-run \
  --name flight-delays-dev-workflow \
  --run-id <run-id>

# List recent job runs
aws glue get-job-runs \
  --job-name flight-delays-dev-data-cleaning \
  --max-results 5
```

## 🔍 Data Inspection Commands

```bash
# List data in each layer
aws s3 ls s3://flight-delays-dev-raw/ --recursive
aws s3 ls s3://flight-delays-dev-silver/ --recursive
aws s3 ls s3://flight-delays-dev-gold/ --recursive

# Download sample data
aws s3 cp s3://flight-delays-dev-gold/year=2024/month=11/ ./gold_sample/ --recursive

# Query with Athena (after crawlers run)
aws athena start-query-execution \
  --query-string "SELECT * FROM flight_delays_gold_table LIMIT 10" \
  --result-configuration OutputLocation=s3://your-athena-results/
```

## 🛠️ Maintenance Commands

```bash
# Update Glue scripts (after editing locally)
terraform apply

# View Terraform outputs
terraform output

# Refresh Terraform state
terraform refresh

# View specific output
terraform output raw_bucket_name

# Format Terraform files
terraform fmt -recursive

# Validate configuration
terraform validate
```

## 🚨 Error Recovery Commands

```bash
# Download DLQ errors
aws s3 cp s3://flight-delays-dev-dlq/cleaning_errors/ ./errors/ --recursive

# Clear DLQ after fixing
aws s3 rm s3://flight-delays-dev-dlq/cleaning_errors/ --recursive

# Reprocess data (clear Silver/Gold first)
aws s3 rm s3://flight-delays-dev-silver/ --recursive
aws s3 rm s3://flight-delays-dev-gold/ --recursive
aws glue start-workflow-run --name flight-delays-dev-workflow

# Archive old DLQ errors
aws s3 mv s3://flight-delays-dev-dlq/cleaning_errors/ \
  s3://flight-delays-dev-dlq/archive/$(date +%Y%m%d)/ --recursive
```

## 📧 SNS Management

```bash
# List SNS subscriptions
aws sns list-subscriptions

# Confirm subscription manually (if needed)
aws sns confirm-subscription \
  --topic-arn <topic-arn> \
  --token <token-from-email>

# Test SNS alert
aws sns publish \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --message "Test alert from Flight Delays Pipeline"
```

## 🔐 IAM & Security Commands

```bash
# List IAM roles created
aws iam list-roles | grep flight-delays

# View role policies
aws iam list-attached-role-policies --role-name flight-delays-dev-lambda-role

# Check S3 bucket encryption
aws s3api get-bucket-encryption --bucket flight-delays-dev-raw

# Verify public access is blocked
aws s3api get-public-access-block --bucket flight-delays-dev-raw
```

## 📈 Cost Monitoring

```bash
# Get cost for last 7 days (requires AWS CLI v2)
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --filter file://filter.json

# Check S3 storage usage
aws s3 ls s3://flight-delays-dev-raw --recursive --summarize --human-readable

# List Glue job runs with duration
aws glue get-job-runs \
  --job-name flight-delays-dev-data-cleaning \
  --query 'JobRuns[*].[Id,ExecutionTime,JobRunState]' \
  --output table
```

## 🧪 Testing Commands

```bash
# Upload test data
head -n 1000 flight_delays.csv > test_data.csv
aws s3 cp test_data.csv s3://flight-delays-dev-raw/historical/test/

# Upload malformed data (to test DLQ)
echo "invalid,data,format" > bad_data.csv
aws s3 cp bad_data.csv s3://flight-delays-dev-raw/historical/

# Trigger job and watch for DLQ
aws glue start-job-run --job-name flight-delays-dev-data-cleaning
sleep 60
aws s3 ls s3://flight-delays-dev-dlq/cleaning_errors/ --recursive
```

## 🔄 Schedule Management

```bash
# List EventBridge rules
aws events list-rules --name-prefix flight-delays

# Disable schedule (pause pipeline)
aws events disable-rule --name flight-delays-dev-lambda-schedule

# Enable schedule
aws events enable-rule --name flight-delays-dev-lambda-schedule

# View schedule details
aws events describe-rule --name flight-delays-dev-lambda-schedule
```

## 📋 Glue Catalog Commands

```bash
# List databases
aws glue get-databases

# List tables in database
aws glue get-tables --database-name flight-delays-dev-db

# Get table schema
aws glue get-table \
  --database-name flight-delays-dev-db \
  --name flight_delays_gold_table

# Get table statistics
aws glue get-table \
  --database-name flight-delays-dev-db \
  --name flight_delays_gold_table \
  --query 'Table.StorageDescriptor.Columns'
```

## 🔧 Common Troubleshooting

```bash
# Check if resources exist
aws s3 ls | grep flight-delays
aws lambda list-functions | grep wikipedia-scraper
aws glue list-jobs | grep flight-delays

# Verify IAM role trust relationships
aws iam get-role --role-name flight-delays-dev-lambda-role

# Check Lambda environment variables
aws lambda get-function-configuration \
  --function-name flight-delays-dev-wikipedia-scraper \
  --query 'Environment'

# Test Lambda permissions
aws lambda invoke \
  --function-name flight-delays-dev-wikipedia-scraper \
  --log-type Tail \
  --query 'LogResult' \
  --output text \
  response.json | base64 -d
```

## 📦 Backup & Restore

```bash
# Backup Terraform state
cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d)

# Export Glue scripts
aws s3 cp s3://flight-delays-dev-raw/glue-scripts/ ./backup/glue-scripts/ --recursive

# Backup data
aws s3 sync s3://flight-delays-dev-gold/ ./backup/gold-data/

# Restore data
aws s3 sync ./backup/gold-data/ s3://flight-delays-dev-gold/
```

## 🎯 Production Deployment Checklist

```bash
# 1. Update environment
sed -i 's/environment = "dev"/environment = "prod"/' terraform.tfvars

# 2. Update resource prefix
sed -i 's/resource_prefix = "flight-delays"/resource_prefix = "flight-delays-prod"/' terraform.tfvars

# 3. Update alert email
nano terraform.tfvars  # Set production email

# 4. Plan deployment
terraform plan -out=prod.tfplan

# 5. Review plan carefully
terraform show prod.tfplan

# 6. Apply
terraform apply prod.tfplan

# 7. Verify
terraform output
aws s3 ls | grep flight-delays-prod
```

## 📞 Quick Help

| Need | Command |
|------|---------|
| View all outputs | `terraform output` |
| Check bucket names | `terraform output \| grep bucket_name` |
| Get SNS topic | `terraform output sns_topic_arn` |
| List all resources | `terraform state list` |
| Show resource details | `terraform state show <resource>` |

---

**Pro Tip**: Save commonly used commands as shell aliases in `~/.bashrc` or `~/.zshrc`:

```bash
alias fd-deploy='cd ~/Projects/Y3S1/IS459-Project/terraform && terraform apply'
alias fd-trigger='aws glue start-workflow-run --name flight-delays-dev-workflow'
alias fd-logs='aws logs tail /aws-glue/jobs/output --follow'
alias fd-dlq='aws s3 ls s3://flight-delays-dev-dlq/ --recursive'
```

