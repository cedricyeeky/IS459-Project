# Mock Flight Data API - Quick Reference

A production-ready mock API that generates realistic flight reliability data for your ECS scraper.

## 🎯 Business Question
**"By optimizing Flight Reliability, we aim to improve travel satisfaction for travelers and improve the reputation of booking platforms via data transparency."**

## 🚀 Quick Start

### Option 1: Docker Compose (Easiest)
```bash
cd mock_api
./start.sh docker
```

### Option 2: Docker Manual
```bash
cd mock_api
docker-compose up -d
```

### Option 3: Local Development
```bash
cd mock_api
./start.sh local
```

API will be available at: **http://localhost:5000**

## 📊 API Endpoints

| Endpoint | Description | Example |
|----------|-------------|---------|
| `GET /` | API documentation | `curl http://localhost:5000/` |
| `GET /health` | Health check | `curl http://localhost:5000/health` |
| `GET /api/v1/flights` | Get flight data | `curl "http://localhost:5000/api/v1/flights?limit=50"` |
| `GET /api/v1/flights/realtime` | Real-time updates | `curl "http://localhost:5000/api/v1/flights/realtime"` |
| `GET /api/v1/stats` | API statistics | `curl "http://localhost:5000/api/v1/stats"` |

## 🧪 Test the API

```bash
cd mock_api
./start.sh test
```

Or manually:
```bash
# Get 10 delayed flights
curl "http://localhost:5000/api/v1/flights?status=DELAYED&limit=10" | jq '.summary_statistics'

# Get Delta Airlines flights
curl "http://localhost:5000/api/v1/flights?carrier=DL&limit=20" | jq '.flights[0]'

# Get real-time updates
curl "http://localhost:5000/api/v1/flights/realtime?limit=30" | jq '.metadata'
```

## 📦 What You Get

Each API response includes:

### Summary Statistics
- On-time rate (%)
- Delay rate (%)
- Cancellation rate (%)
- Average delay minutes

### Flight Records
Each flight includes:
- **Identification**: flight_number, tail_number, aircraft_type
- **Carrier Info**: carrier_code, carrier_name, reliability_score
- **Route**: origin/destination airports and cities
- **Schedule**: scheduled and actual departure/arrival times
- **Delays**: delay minutes, delay reasons, cascade risk
- **Reliability**: on_time flag, reliability_band (Excellent/Good/Fair/Poor)
- **Metadata**: date, day of week, timestamp

### Sample Response
```json
{
  "metadata": {
    "total_records": 100,
    "timestamp": "2024-11-04T15:30:00Z"
  },
  "summary_statistics": {
    "on_time_rate": 78.5,
    "delay_rate": 18.2,
    "cancellation_rate": 3.3,
    "average_delay_minutes": 42.5
  },
  "flights": [
    {
      "flight_number": "AA1234",
      "carrier_code": "AA",
      "carrier_name": "American Airlines",
      "origin_airport": "ATL",
      "destination_airport": "LAX",
      "scheduled_departure": "2024-11-04T08:30:00",
      "actual_departure": "2024-11-04T08:47:00",
      "arrival_delay_minutes": 17,
      "delay_reason": "CARRIER",
      "reliability_band": "GOOD",
      "on_time": false,
      "cascade_risk": false
    }
  ]
}
```

## 🔄 Integration with ECS Scraper

### Architecture
```
EventBridge (every 15 min)
    ↓
ECS Scraper Task
    ↓
Mock API (GET /api/v1/flights/realtime)
    ↓
S3 Raw Bucket (scraped/flights/YYYY/MM/DD/)
    ↓
Glue Jobs (cleaning & features)
```

### Deploy to AWS

Full deployment guide: [INTEGRATION_GUIDE.md](./INTEGRATION_GUIDE.md)

Quick steps:
1. Build and push Docker images to ECR
2. Create ECS tasks for Mock API and Scraper
3. Set up EventBridge schedule (every 15 minutes)
4. Scraper uploads JSON to S3
5. Glue jobs process the data

## 📁 Files in This Directory

| File | Purpose |
|------|---------|
| `app.py` | Main Flask API application |
| `Dockerfile` | Docker image for Mock API |
| `Dockerfile.scraper` | Docker image for ECS scraper |
| `docker-compose.yml` | Local development setup |
| `requirements.txt` | Python dependencies |
| `scraper_example.py` | Example scraper for ECS |
| `test_api.py` | API test suite |
| `start.sh` | Quick start script |
| `README.md` | Detailed documentation |
| `INTEGRATION_GUIDE.md` | AWS deployment guide |

## 🎲 Data Characteristics

The API generates realistic flight data with:

- **8 carriers** with reliability scores: 72-88%
- **15 major US airports** (ATL, LAX, ORD, DFW, etc.)
- **Realistic delay patterns**:
  - Peak hours (6-9 AM, 4-8 PM): 50% more delays
  - Red-eye flights (12-5 AM): 30% fewer delays
- **Delay reasons** with real distributions:
  - Carrier: 30%
  - Weather: 25%
  - Late Aircraft: 20%
  - NAS: 20%
  - Security: 5%
- **Cancellation rates**: 0-3% based on carrier
- **Status tracking**: SCHEDULED → DEPARTED → ARRIVED/DELAYED/CANCELLED

## ⚙️ Configuration

Environment variables (`.env` file):

```bash
PORT=5000
DEBUG=False
ROWS_PER_REQUEST=100
```

## 🔍 Monitoring

### View Logs
```bash
# Docker Compose
./start.sh logs

# Or
docker-compose logs -f
```

### Check Status
```bash
curl http://localhost:5000/health
curl http://localhost:5000/api/v1/stats
```

## 🧹 Cleanup

```bash
# Stop API
./start.sh stop

# Or
docker-compose down

# Remove images
docker rmi flight-mock-api
```

## 📊 Aligns with Your Gold Layer Outputs

The mock API data structure matches your pipeline's gold layer:

| Gold Layer Output | API Field |
|-------------------|-----------|
| `flight_features` | All flight records with delay/reliability metrics |
| `cascade_metrics` | `cascade_risk` flag for cascade analysis |
| `reliability_metrics` | `reliability_band`, `on_time`, carrier scores |

## 💡 Tips

1. **For Development**: Use `./start.sh local` to run without Docker
2. **For Testing**: Run `./start.sh test` to verify all endpoints
3. **For Production**: Deploy to ECS using `INTEGRATION_GUIDE.md`
4. **For Debugging**: Check logs with `./start.sh logs`

## 🤝 Support

- Full documentation: [README.md](./README.md)
- AWS deployment: [INTEGRATION_GUIDE.md](./INTEGRATION_GUIDE.md)
- Test the API: `./start.sh test`

## 📈 Next Steps

1. ✅ Start the Mock API locally
2. ✅ Test the endpoints
3. ✅ Deploy to ECS
4. ✅ Set up EventBridge schedule
5. ⏭️ Verify S3 uploads
6. ⏭️ Update Glue jobs to process scraped data
7. ⏭️ Add monitoring and alerts

---

**Ready to start?** Run: `./start.sh docker` 🚀
