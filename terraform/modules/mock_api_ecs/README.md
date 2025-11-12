# Mock API ECS Module

This module creates the infrastructure for running a Mock Flight API service on ECS with an Application Load Balancer.

## Structure

```
mock_api_ecs/
├── main.tf          # ECS cluster, service, task definition, ALB, security groups
├── outputs.tf       # Module outputs (ALB DNS, ECS cluster ARN, etc.)
├── variables.tf     # Module variables
└── src/            # Mock API application source code
    ├── app.py              # Flask API application
    ├── Dockerfile          # Docker image definition
    ├── requirements.txt    # Python dependencies
    ├── start.sh            # Application startup script
    ├── docker-compose.yml  # Local development setup
    ├── test_api.py         # API tests
    ├── README.md           # Application documentation
    ├── QUICK_START.md      # Quick start guide
    ├── INTEGRATION_GUIDE.md # Integration guide
    └── docs/               # Additional documentation
```

## What it Creates

- **VPC Resources**: Optional VPC, subnets, NAT gateway, internet gateway
- **ECS Cluster**: Fargate cluster with Container Insights enabled
- **ECS Service**: Mock API service with 2 tasks, health checks
- **Application Load Balancer**: Public-facing ALB with HTTP listener
- **Security Groups**: ALB and ECS security groups with proper ingress/egress rules
- **CloudWatch Log Groups**: Logs for Mock API service
- **ECR Repository**: Docker image repository for Mock API

## Usage

The module is called from `terraform/longterm/main.tf`:

```hcl
module "compute" {
  source = "../modules/mock_api_ecs"
  
  mock_api_image = "${aws_ecr_repository.mock_api.repository_url}:latest"
  # ... other variables
}
```

## Building and Deploying

To build and deploy the Mock API Docker image:

```bash
# Build locally
cd terraform/modules/mock_api_ecs/src
docker build -t mock-api:latest .

# Or use docker-compose for local testing
docker-compose up

# Push to ECR (done via CI/CD or manual process)
```

## Application Details

The Mock API (`src/app.py`):
- Provides flight and weather data endpoints for testing
- Supports real-time and historical flight data queries
- Returns mock weather observations for airports
- Includes health check endpoint at `/health`
- Runs on port 5200 with gunicorn

## Endpoints

- `GET /health` - Health check
- `GET /api/v1/flights/realtime` - Real-time flight data
- `GET /api/v1/weather` - Weather observations
- See `src/README.md` for full API documentation

## Environment Variables

Set in the ECS task definition:
- `FLASK_ENV`: Flask environment (production/development)
- `PORT`: Application port (default: 5200)
