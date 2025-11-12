# Mock Flight API - Bruno Documentation

This Bruno collection provides complete API documentation and testing capabilities for the Mock Flight Data API.

## 🚀 Quick Start

### 1. Install Bruno
Download Bruno from [usebruno.com](https://www.usebruno.com/)

### 2. Open Collection
- Launch Bruno
- Click "Open Collection"
- Navigate to this `bruno-docs` folder
- Select the folder containing `bruno.json`

### 3. Select Environment
Choose the appropriate environment:
- **Production**: AWS ECS deployment (ALB endpoint)
- **Local**: Local development (`localhost:5200`)

## 📋 Available Endpoints

### Core Endpoints

1. **API Root** - `/`
   - Get complete API documentation
   - View available endpoints and parameters
   - Understand business focus and metrics

2. **Health Check** - `/health`
   - Verify API is running
   - Used by ECS load balancers
   - Returns status, timestamp, and version

### Flight Data Endpoints

3. **Get Flights (All)** - `/api/v1/flights`
   - Retrieve flight data with filtering
   - Default: 250 records
   - Supports multiple query parameters

4. **Get Flights (By Date)** - `/api/v1/flights?date=YYYY-MM-DD`
   - Filter by specific date
   - Historical or future data
   - Example: `date=2025-11-10`

5. **Get Flights (By Carrier)** - `/api/v1/flights?carrier=AA`
   - Filter by airline code
   - Carrier-specific performance
   - 24 carriers available (AA, DL, UA, WN, etc.)

6. **Get Flights (By Route)** - `/api/v1/flights?origin=ORD&destination=LAX`
   - Filter by origin and destination
   - Route-specific analysis
   - 20 major airports available

7. **Get Flights (Delayed Only)** - `/api/v1/flights?status=DELAYED`
   - Filter by flight status
   - Includes delay reasons and metrics
   - Statuses: SCHEDULED, DEPARTED, ARRIVED, DELAYED, CANCELLED

8. **Get Realtime Flights** - `/api/v1/flights/realtime`
   - **Primary endpoint for data pipeline**
   - 15-minute window (matches EventBridge schedule)
   - Random 200-300 records by default
   - Optimized for fast generation

9. **Get Realtime Flights (Custom Limit)** - `/api/v1/flights/realtime?limit=500`
   - Override default record count
   - Up to 1000 records per request
   - For testing or batch processing

10. **Get API Statistics** - `/api/v1/stats`
    - API health metrics
    - Carrier reliability rankings
    - Data availability information

11. **Get Flights (Complex Filter)** - Multiple parameters
    - Combine carrier + origin + status + date
    - Advanced filtering scenarios
    - Multi-dimensional analysis

## 🔍 Query Parameters

### Available Parameters

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `limit` | integer | Number of records (max: 1000) | `limit=250` |
| `date` | string | Filter by date (YYYY-MM-DD) | `date=2025-11-10` |
| `carrier` | string | Airline code | `carrier=AA` |
| `origin` | string | Origin airport code | `origin=ORD` |
| `destination` | string | Destination airport code | `destination=LAX` |
| `status` | string | Flight status | `status=DELAYED` |

### Flight Statuses
- `SCHEDULED` - On schedule, not departed
- `DEPARTED` - Left the gate
- `ARRIVED` - Reached destination
- `DELAYED` - Experiencing delays
- `CANCELLED` - Flight cancelled

### Major Carriers (24 total)
**Major US Airlines:**
- `AA` - American Airlines
- `DL` - Delta Air Lines
- `UA` - United Air Lines
- `WN` - Southwest Airlines
- `B6` - JetBlue Airways
- `AS` - Alaska Airlines
- `NK` - Spirit Air Lines
- `F9` - Frontier Airlines
- `G4` - Allegiant Air

**Regional Airlines:**
- `OO` - Skywest Airlines
- `MQ` - American Eagle
- `9E` - Pinnacle Airlines
- `YV` - Mesa Airlines
- `OH` - Comair
- `EV` - Atlantic Southeast
- And more...

### Major Airports (20 total)
**High Traffic:**
- `ORD` - Chicago O'Hare
- `ATL` - Atlanta
- `DFW` - Dallas/Fort Worth
- `LAX` - Los Angeles
- `PHX` - Phoenix
- `DEN` - Denver
- `SFO` - San Francisco
- `EWR` - Newark
- `BOS` - Boston
- `SEA` - Seattle
- And more...

## 📊 Response Structure

### Metadata
```json
{
  "metadata": {
    "total_records": 250,
    "timestamp": "2025-11-10T12:00:00.000000",
    "date_filter": "2025-11-10",
    "api_version": "v1"
  }
}
```

### Summary Statistics
```json
{
  "summary_statistics": {
    "on_time_rate": 82.5,
    "delay_rate": 15.2,
    "cancellation_rate": 2.3,
    "average_delay_minutes": 45.8,
    "total_flights": 250,
    "on_time_flights": 206,
    "delayed_flights": 38,
    "cancelled_flights": 6
  }
}
```

### Flight Record Example
```json
{
  "flight_id": "AA1234_20251110_ORD_LAX",
  "flight_number": "AA1234",
  "tail_number": "N123AA",
  "aircraft_type": "Boeing 737",
  
  "carrier_code": "AA",
  "carrier_name": "American Airlines Inc.",
  "carrier_reliability_score": 0.82,
  
  "origin_airport": "ORD",
  "origin_city": "Chicago",
  "destination_airport": "LAX",
  "destination_city": "Los Angeles",
  
  "scheduled_departure": "2025-11-10T14:30:00",
  "scheduled_arrival": "2025-11-10T17:45:00",
  "actual_departure": "2025-11-10T14:45:00",
  "actual_arrival": "2025-11-10T18:00:00",
  
  "departure_delay_minutes": 15,
  "arrival_delay_minutes": 15,
  "delay_reason": "CARRIER",
  "is_delayed": true,
  "is_cancelled": false,
  
  "status": "ARRIVED",
  "on_time": true,
  "cascade_risk": false,
  "reliability_band": "EXCELLENT",
  
  "flight_date": "2025-11-10",
  "day_of_week": "Sunday",
  "hour_of_day": 14,
  "is_weekend": true
}
```

## 🎯 Business Metrics

### Reliability Bands
- `EXCELLENT` - Arrival delay ≤15 minutes
- `GOOD` - Arrival delay 16-30 minutes
- `FAIR` - Arrival delay 31-60 minutes
- `POOR` - Arrival delay >60 minutes or cancelled

### Delay Reasons
- `WEATHER` - Weather-related delays (30-240 min)
- `CARRIER` - Carrier/airline issues (15-120 min)
- `LATE_AIRCRAFT` - Previous flight delayed (20-180 min)
- `NAS` - National Aviation System (15-90 min)
- `SECURITY` - Security screening (10-60 min)

### Key Metrics
- **On-time Performance**: Arrival delay ≤15 minutes
- **Cascade Risk**: Departure delay >60 minutes (may affect subsequent flights)
- **Carrier Reliability Score**: 0.0 (worst) to 1.0 (best)

## 🔄 Real-time Endpoint vs General Endpoint

### `/api/v1/flights/realtime` (Recommended for Pipeline)
- ✅ Optimized for speed
- ✅ 15-minute time window
- ✅ Random 200-300 records (realistic variability)
- ✅ Matches EventBridge schedule
- ✅ No filtering needed
- 🎯 **Use for: ECS scraper / data pipeline**

### `/api/v1/flights` (General Purpose)
- ✅ Full filtering capabilities
- ✅ Historical/future date support
- ✅ Multi-parameter filtering
- ⏱️ Slower with many filters
- 🎯 **Use for: Ad-hoc queries / analysis**

## 🌐 Environments

### Production Environment
```
Base URL: http://flight-mock-api-prod-alb-2052111428.us-east-1.elb.amazonaws.com
API Version: v1
```

**Infrastructure:**
- AWS ECS Fargate (2 tasks)
- Application Load Balancer
- CloudWatch Logs: `/ecs/flight-mock-api-prod/mock-api`

### Local Environment
```
Base URL: http://localhost:5200
API Version: v1
```

**To run locally:**
```bash
cd mock_api
docker-compose up
# or
python app.py
```

## 📝 Usage Examples

### Test API Health
```bash
curl http://flight-mock-api-prod-alb-2052111428.us-east-1.elb.amazonaws.com/health
```

### Get Realtime Data (Pipeline Use)
```bash
curl http://flight-mock-api-prod-alb-2052111428.us-east-1.elb.amazonaws.com/api/v1/flights/realtime
```

### Filter by Carrier and Date
```bash
curl "http://flight-mock-api-prod-alb-2052111428.us-east-1.elb.amazonaws.com/api/v1/flights?carrier=AA&date=2025-11-10&limit=100"
```

### Get API Statistics
```bash
curl http://flight-mock-api-prod-alb-2052111428.us-east-1.elb.amazonaws.com/api/v1/stats
```

## 🛠️ Testing in Bruno

1. **Select request** from the left sidebar
2. **Click "Send"** to execute
3. **View response** in the right panel
4. **Modify parameters** in the "Params" tab
5. **Switch environments** using the dropdown

## 📚 Additional Resources

- **API Code**: `/mock_api/app.py`
- **Integration Guide**: `/mock_api/INTEGRATION_GUIDE.md`
- **Quick Start**: `/mock_api/QUICK_START.md`
- **Deployment**: `/terraform/longterm/`

## 🔗 Related Documentation

- [AWS ECS Deployment](../DEPLOYMENT_SUMMARY.md)
- [Testing Guide](../TESTING_GUIDE.md)
- [Quick Reference](../QUICK_REFERENCE.md)

## 📊 Performance Notes

- Default response time: <500ms for realtime endpoint
- Maximum records per request: 1000
- Default records (realtime): Random 200-300
- Recommended refresh interval: 15 minutes (matches EventBridge)

## 🤝 Support

For issues or questions:
1. Check API `/` endpoint for documentation
2. Review `/health` endpoint for service status
3. Check CloudWatch logs: `/ecs/flight-mock-api-prod/mock-api`
4. Verify ALB endpoint is accessible

---

**API Version**: v1  
**Last Updated**: November 2025  
**Status**: Production Ready ✅
