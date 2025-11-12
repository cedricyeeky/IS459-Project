# Scraper ECS Module

This module creates the infrastructure for running a scheduled ECS task that scrapes flight and weather data.

## Structure

```
scraper_ecs/
├── main.tf           # ECS task definition, EventBridge schedule, IAM roles
├── outputs.tf        # Module outputs
├── variables.tf      # Module variables
└── src/             # Scraper application source code
    ├── app.py           # Main scraper application
    ├── Dockerfile       # Docker image definition
    ├── requirements.txt # Python dependencies
    ├── redeploy.sh      # Deployment script
    ├── DEPLOYMENT.md    # Deployment documentation
    ├── README.md        # Application documentation
    └── test_error_scenarios.py  # DLQ testing script
```

## What it Creates

- **ECS Task Definition**: Defines the scraper container configuration
- **EventBridge Schedule**: Triggers the scraper every 15 minutes
- **IAM Roles**: Execution and task roles for ECS
- **CloudWatch Log Group**: Stores scraper logs

## Usage

The module is called from `terraform/longterm/main.tf`:

```hcl
module "scraper" {
  source = "../modules/scraper_ecs"
  
  scraper_image = "${aws_ecr_repository.scraper.repository_url}:latest"
  # ... other variables
}
```

## Building and Deploying

To build and deploy the scraper Docker image:

```bash
cd terraform/modules/scraper_ecs/src
./redeploy.sh
```

This will:
1. Build the Docker image
2. Push to ECR
3. The next scheduled run will use the new image

## Application Details

The scraper application (`src/app.py`):
- Fetches weather and flight data from the Mock API
- Uploads data to S3 with flat structure: `s3://bucket/scraped/{weather|flights}/filename.json`
- Logs errors to DLQ bucket for monitoring
- Runs every 15 minutes via EventBridge

## Environment Variables

Set in the ECS task definition:
- `API_ENDPOINT`: Mock API endpoint (ALB DNS)
- `S3_BUCKET`: Raw data S3 bucket name
- `AWS_REGION`: AWS region
- `REQUEST_TIMEOUT`: HTTP request timeout
