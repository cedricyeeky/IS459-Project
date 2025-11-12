"""
Mock Flight Data API for ECS Scraper
=====================================
Returns realistic flight data with reliability metrics every 15 minutes.

Business Focus: Flight Reliability & Travel Satisfaction
- On-time performance metrics
- Delay patterns and causes
- Carrier reliability scores
- Route performance data
- Real-time flight status updates
"""

from flask import Flask, jsonify, request
from datetime import datetime, timedelta
import random
import string
import os

app = Flask(__name__)

# Configuration
API_VERSION = "v1"
ROWS_PER_REQUEST = int(os.getenv('ROWS_PER_REQUEST', 250))  # Default 250 records per API call

# Realistic data pools - Based on carriers.xls
CARRIERS = [
    # Major US Airlines
    {'code': 'AA', 'name': 'American Airlines Inc.', 'reliability_score': 0.82},
    {'code': 'DL', 'name': 'Delta Air Lines Inc.', 'reliability_score': 0.88},
    {'code': 'UA', 'name': 'United Air Lines Inc.', 'reliability_score': 0.79},
    {'code': 'WN', 'name': 'Southwest Airlines Co.', 'reliability_score': 0.85},
    {'code': 'B6', 'name': 'JetBlue Airways', 'reliability_score': 0.81},
    {'code': 'AS', 'name': 'Alaska Airlines Inc.', 'reliability_score': 0.87},
    {'code': 'NK', 'name': 'Spirit Air Lines', 'reliability_score': 0.72},
    {'code': 'F9', 'name': 'Frontier Airlines Inc.', 'reliability_score': 0.74},
    {'code': 'G4', 'name': 'Allegiant Air', 'reliability_score': 0.71},
    
    # Regional/Commuter Airlines
    {'code': 'OO', 'name': 'Skywest Airlines Inc.', 'reliability_score': 0.80},
    {'code': 'MQ', 'name': 'American Eagle Airlines Inc.', 'reliability_score': 0.77},
    {'code': '9E', 'name': 'Pinnacle Airlines Inc.', 'reliability_score': 0.79},
    {'code': 'YV', 'name': 'Mesa Airlines Inc.', 'reliability_score': 0.76},
    {'code': 'OH', 'name': 'Comair Inc.', 'reliability_score': 0.75},
    {'code': 'EV', 'name': 'Atlantic Southeast Airlines', 'reliability_score': 0.78},
    {'code': 'YX', 'name': 'Midwest Airline, Inc.', 'reliability_score': 0.77},
    {'code': 'XE', 'name': 'Expressjet Airlines Inc.', 'reliability_score': 0.73},
    {'code': '9K', 'name': 'Cape Air', 'reliability_score': 0.74},
    
    # Legacy/Historical Airlines (for historical data)
    {'code': 'CO', 'name': 'Continental Air Lines Inc.', 'reliability_score': 0.83},
    {'code': 'US', 'name': 'US Airways Inc.', 'reliability_score': 0.80},
    {'code': 'NW', 'name': 'Northwest Airlines Inc.', 'reliability_score': 0.82},
    {'code': 'TW', 'name': 'Trans World Airways LLC', 'reliability_score': 0.75},
    {'code': 'HP', 'name': 'America West Airlines Inc.', 'reliability_score': 0.78},
    {'code': 'FL', 'name': 'AirTran Airways Corporation', 'reliability_score': 0.81},
]

AIRPORTS = [
    {'code': 'ORD', 'city': 'Chicago', 'traffic_level': 'high'},
    {'code': 'ATL', 'city': 'Atlanta', 'traffic_level': 'high'},
    {'code': 'DFW', 'city': 'Dallas/Fort Worth', 'traffic_level': 'high'},
    {'code': 'LAX', 'city': 'Los Angeles', 'traffic_level': 'high'},
    {'code': 'PHX', 'city': 'Phoenix', 'traffic_level': 'high'},
    {'code': 'DEN', 'city': 'Denver', 'traffic_level': 'high'},
    {'code': 'DTW', 'city': 'Detroit', 'traffic_level': 'high'},
    {'code': 'IAH', 'city': 'Houston', 'traffic_level': 'high'},
    {'code': 'MSP', 'city': 'Minneapolis', 'traffic_level': 'high'},
    {'code': 'SFO', 'city': 'San Francisco', 'traffic_level': 'high'},
    {'code': 'STL', 'city': 'St. Louis', 'traffic_level': 'medium'},
    {'code': 'EWR', 'city': 'Newark', 'traffic_level': 'high'},
    {'code': 'LAS', 'city': 'Las Vegas', 'traffic_level': 'high'},
    {'code': 'CLT', 'city': 'Charlotte', 'traffic_level': 'high'},
    {'code': 'LGA', 'city': 'New York LaGuardia', 'traffic_level': 'high'},
    {'code': 'BOS', 'city': 'Boston', 'traffic_level': 'high'},
    {'code': 'PHL', 'city': 'Philadelphia', 'traffic_level': 'high'},
    {'code': 'PIT', 'city': 'Pittsburgh', 'traffic_level': 'medium'},
    {'code': 'SLC', 'city': 'Salt Lake City', 'traffic_level': 'medium'},
    {'code': 'SEA', 'city': 'Seattle', 'traffic_level': 'high'},
]

DELAY_REASONS = [
    {'code': 'WEATHER', 'description': 'Weather delay', 'weight': 0.25},
    {'code': 'CARRIER', 'description': 'Carrier delay', 'weight': 0.30},
    {'code': 'NAS', 'description': 'National Aviation System delay', 'weight': 0.20},
    {'code': 'SECURITY', 'description': 'Security delay', 'weight': 0.05},
    {'code': 'LATE_AIRCRAFT', 'description': 'Late aircraft delay', 'weight': 0.20},
]

FLIGHT_STATUSES = ['SCHEDULED', 'DEPARTED', 'ARRIVED', 'DELAYED', 'CANCELLED']

AIRCRAFT_TYPES = ['Boeing 737', 'Airbus A320', 'Boeing 777', 'Airbus A330', 
                 'Boeing 787', 'Airbus A350', 'Embraer E175', 'Boeing 757']

# Weather-related data pools
WEATHER_PHRASES = [
    'Clear', 'Partly Cloudy', 'Mostly Cloudy', 'Cloudy', 'Overcast',
    'Light Rain', 'Rain', 'Heavy Rain', 'Thunderstorms', 'Scattered Thunderstorms',
    'Light Snow', 'Snow', 'Heavy Snow', 'Freezing Rain', 'Sleet',
    'Fog', 'Haze', 'Mist', 'Drizzle', 'Showers',
    'Windy', 'Fair', 'Breezy', 'Scattered Clouds', 'Few Clouds'
]

CLOUD_COVERAGE = ['CLR', 'FEW', 'SCT', 'BKN', 'OVC']  # Clear, Few, Scattered, Broken, Overcast


def generate_flight_number(carrier_code):
    """Generate realistic flight number."""
    return f"{carrier_code}{random.randint(100, 9999)}"


def generate_tail_number():
    """Generate realistic aircraft tail number."""
    return f"N{random.randint(100, 999)}{random.choice(string.ascii_uppercase)}{random.choice(string.ascii_uppercase)}"


def generate_weather_record(airport_code, airport_city, timestamp_base):
    """Generate a single realistic weather observation record.
    
    Args:
        airport_code: Airport ICAO/IATA code
        airport_city: Airport city name
        timestamp_base: Base timestamp for weather observation
    """
    # Generate observation ID
    obs_id = f"{airport_code}_{timestamp_base.strftime('%Y%m%d%H%M')}"
    
    # Valid time in GMT (epoch timestamp)
    valid_time_gmt = int(timestamp_base.timestamp())
    
    # Select weather phrase based on realistic distribution
    # Clear/fair weather is more common than severe weather
    weather_weights = [0.25] + [0.15] * 4 + [0.08] * 5 + [0.03] * 5 + [0.04] * 10
    wx_phrase = random.choices(WEATHER_PHRASES, weights=weather_weights)[0]
    
    # Temperature (°F) - varies by weather condition
    if 'Snow' in wx_phrase or 'Freezing' in wx_phrase:
        temp = random.randint(15, 35)
    elif 'Rain' in wx_phrase or 'Thunderstorm' in wx_phrase:
        temp = random.randint(45, 75)
    else:
        temp = random.randint(35, 85)
    
    # Precipitation hourly (inches) - based on weather phrase
    if 'Heavy Rain' in wx_phrase or 'Thunderstorms' in wx_phrase:
        precip_hrly = round(random.uniform(0.3, 1.5), 2)
    elif 'Rain' in wx_phrase or 'Drizzle' in wx_phrase or 'Showers' in wx_phrase:
        precip_hrly = round(random.uniform(0.05, 0.3), 2)
    elif 'Light Rain' in wx_phrase:
        precip_hrly = round(random.uniform(0.01, 0.1), 2)
    else:
        precip_hrly = 0.0
    
    # Snow hourly (inches) - based on weather phrase
    if 'Heavy Snow' in wx_phrase:
        snow_hrly = round(random.uniform(0.5, 3.0), 2)
    elif 'Snow' in wx_phrase:
        snow_hrly = round(random.uniform(0.1, 0.5), 2)
    elif 'Light Snow' in wx_phrase:
        snow_hrly = round(random.uniform(0.01, 0.15), 2)
    else:
        snow_hrly = 0.0
    
    # Wind speed (mph) - based on weather condition
    if 'Thunderstorms' in wx_phrase or 'Windy' in wx_phrase:
        wspd = random.randint(20, 45)
    elif 'Breezy' in wx_phrase or 'Rain' in wx_phrase:
        wspd = random.randint(10, 20)
    else:
        wspd = random.randint(0, 15)
    
    # Cloud coverage - based on weather phrase
    if 'Clear' in wx_phrase or 'Fair' in wx_phrase:
        clds = 'CLR'
    elif 'Few Clouds' in wx_phrase:
        clds = 'FEW'
    elif 'Partly Cloudy' in wx_phrase or 'Scattered' in wx_phrase:
        clds = 'SCT'
    elif 'Mostly Cloudy' in wx_phrase:
        clds = 'BKN'
    else:  # Cloudy, Overcast, Rain, Snow, etc.
        clds = 'OVC'
    
    # Relative humidity (%) - based on conditions
    if 'Rain' in wx_phrase or 'Snow' in wx_phrase or 'Fog' in wx_phrase:
        rh = random.randint(75, 100)
    elif 'Cloudy' in wx_phrase:
        rh = random.randint(60, 85)
    else:
        rh = random.randint(30, 70)
    
    # Visibility (miles) - based on weather
    if 'Fog' in wx_phrase:
        vis = round(random.uniform(0.25, 2.0), 2)
    elif 'Heavy Rain' in wx_phrase or 'Heavy Snow' in wx_phrase:
        vis = round(random.uniform(1.0, 3.0), 2)
    elif 'Rain' in wx_phrase or 'Snow' in wx_phrase or 'Mist' in wx_phrase:
        vis = round(random.uniform(3.0, 7.0), 2)
    else:
        vis = round(random.uniform(7.0, 10.0), 2)
    
    record = {
        'obs_id': obs_id,
        'airport_code': airport_code,
        'airport_city': airport_city,
        'valid_time_gmt': valid_time_gmt,
        'observation_time': timestamp_base.isoformat(),
        'wx_phrase': wx_phrase,
        'temp': temp,
        'precip_hrly': precip_hrly,
        'snow_hrly': snow_hrly,
        'wspd': wspd,
        'clds': clds,
        'rh': rh,
        'vis': vis,
        'timestamp': datetime.utcnow().isoformat(),
        'data_source': 'mock_api',
        'api_version': API_VERSION,
    }
    
    return record


def calculate_delay_probability(hour, carrier_reliability):
    """
    Calculate delay probability based on time and carrier reliability.
    Higher probability during peak hours and for less reliable carriers.
    """
    # Base delay probability
    base_prob = 1 - carrier_reliability
    
    # Peak hours adjustment (6-9 AM, 4-8 PM have higher delays)
    if 6 <= hour <= 9 or 16 <= hour <= 20:
        base_prob *= 1.5
    elif 0 <= hour <= 5:  # Red-eye flights - lower delays
        base_prob *= 0.7
    
    return min(base_prob, 0.95)


def calculate_delay_minutes(delay_reason):
    """Generate realistic delay minutes based on reason."""
    if delay_reason == 'WEATHER':
        return random.randint(30, 240)
    elif delay_reason == 'CARRIER':
        return random.randint(15, 120)
    elif delay_reason == 'LATE_AIRCRAFT':
        return random.randint(20, 180)
    elif delay_reason == 'NAS':
        return random.randint(15, 90)
    elif delay_reason == 'SECURITY':
        return random.randint(10, 60)
    return 0


def calculate_cancellation_probability(carrier_reliability):
    """Calculate cancellation probability."""
    return (1 - carrier_reliability) * 0.03  # 0-3% cancellation rate


def generate_flight_record(timestamp_base, time_window_minutes=None):
    """Generate a single realistic flight record.
    
    Args:
        timestamp_base: Base timestamp for flight generation
        time_window_minutes: If provided, generate flights within +/- this many minutes of timestamp_base
    """
    carrier = random.choice(CARRIERS)
    origin = random.choice(AIRPORTS)
    destination = random.choice([a for a in AIRPORTS if a['code'] != origin['code']])
    
    flight_number = generate_flight_number(carrier['code'])
    tail_number = generate_tail_number()
    aircraft_type = random.choice(AIRCRAFT_TYPES)
    
    # Scheduled times
    if time_window_minutes:
        # Generate departure time within specified window for faster real-time generation
        offset_minutes = random.randint(-time_window_minutes, time_window_minutes)
        scheduled_departure = timestamp_base + timedelta(minutes=offset_minutes)
        # Round to nearest 15 minutes for realism
        scheduled_minute = (scheduled_departure.minute // 15) * 15
        scheduled_departure = scheduled_departure.replace(minute=scheduled_minute, second=0, microsecond=0)
    else:
        # Generate random time for general use
        scheduled_hour = random.randint(0, 23)
        scheduled_minute = random.choice([0, 15, 30, 45])
        scheduled_departure = timestamp_base.replace(
            hour=scheduled_hour, 
            minute=scheduled_minute, 
            second=0, 
            microsecond=0
        )
    
    # Extract hour for delay probability calculation
    scheduled_hour = scheduled_departure.hour
    
    # Flight duration (1-6 hours depending on distance proxy)
    flight_duration_hours = random.uniform(1.0, 6.0)
    scheduled_arrival = scheduled_departure + timedelta(hours=flight_duration_hours)
    
    # Calculate if flight is delayed or cancelled
    is_cancelled = random.random() < calculate_cancellation_probability(carrier['reliability_score'])
    
    if is_cancelled:
        status = 'CANCELLED'
        departure_delay = None
        arrival_delay = None
        actual_departure = None
        actual_arrival = None
        delay_reason = random.choice(DELAY_REASONS)['code']
        delay_minutes = None
    else:
        delay_prob = calculate_delay_probability(scheduled_hour, carrier['reliability_score'])
        is_delayed = random.random() < delay_prob
        
        if is_delayed:
            delay_reason = random.choices(
                [r['code'] for r in DELAY_REASONS],
                weights=[r['weight'] for r in DELAY_REASONS]
            )[0]
            delay_minutes = calculate_delay_minutes(delay_reason)
            departure_delay = delay_minutes
            
            # Arrival delay may be slightly different due to recovery
            recovery_factor = random.uniform(0.7, 1.2)
            arrival_delay = int(delay_minutes * recovery_factor)
            
            actual_departure = scheduled_departure + timedelta(minutes=departure_delay)
            actual_arrival = scheduled_arrival + timedelta(minutes=arrival_delay)
            
            # Determine status
            now = datetime.utcnow()
            if actual_arrival < now:
                status = 'ARRIVED'
            elif actual_departure < now:
                status = 'DEPARTED'
            else:
                status = 'DELAYED'
        else:
            # On-time flight
            delay_reason = None
            delay_minutes = 0
            departure_delay = 0
            arrival_delay = 0
            actual_departure = scheduled_departure
            actual_arrival = scheduled_arrival
            
            now = datetime.utcnow()
            if actual_arrival < now:
                status = 'ARRIVED'
            elif actual_departure < now:
                status = 'DEPARTED'
            else:
                status = 'SCHEDULED'
    
    # Calculate reliability metrics
    on_time = (not is_cancelled) and (arrival_delay is not None and arrival_delay <= 15)
    cascade_risk = departure_delay > 60 if departure_delay else False
    
    # Reliability band (for traveler-facing metrics)
    if is_cancelled:
        reliability_band = 'POOR'
    elif arrival_delay is None or arrival_delay <= 15:
        reliability_band = 'EXCELLENT'
    elif arrival_delay <= 30:
        reliability_band = 'GOOD'
    elif arrival_delay <= 60:
        reliability_band = 'FAIR'
    else:
        reliability_band = 'POOR'
    
    record = {
        # Flight identification
        'flight_id': f"{flight_number}_{scheduled_departure.strftime('%Y%m%d')}_{origin['code']}_{destination['code']}",
        'flight_number': flight_number,
        'tail_number': tail_number,
        'aircraft_type': aircraft_type,
        
        # Carrier information
        'carrier_code': carrier['code'],
        'carrier_name': carrier['name'],
        'carrier_reliability_score': carrier['reliability_score'],
        
        # Route information
        'origin_airport': origin['code'],
        'origin_city': origin['city'],
        'origin_traffic_level': origin['traffic_level'],
        'destination_airport': destination['code'],
        'destination_city': destination['city'],
        'destination_traffic_level': destination['traffic_level'],
        
        # Schedule information
        'scheduled_departure': scheduled_departure.isoformat(),
        'scheduled_arrival': scheduled_arrival.isoformat(),
        'actual_departure': actual_departure.isoformat() if actual_departure else None,
        'actual_arrival': actual_arrival.isoformat() if actual_arrival else None,
        
        # Delay metrics
        'departure_delay_minutes': departure_delay,
        'arrival_delay_minutes': arrival_delay,
        'delay_reason': delay_reason,
        'is_delayed': is_delayed if not is_cancelled else None,
        'is_cancelled': is_cancelled,
        
        # Status
        'status': status,
        
        # Reliability metrics (aligned with your gold layer outputs)
        'on_time': on_time,
        'cascade_risk': cascade_risk,
        'reliability_band': reliability_band,
        
        # Metadata
        'flight_date': scheduled_departure.strftime('%Y-%m-%d'),
        'day_of_week': scheduled_departure.strftime('%A'),
        'hour_of_day': scheduled_hour,
        'is_weekend': scheduled_departure.weekday() >= 5,
        'timestamp': datetime.utcnow().isoformat(),
        'data_source': 'mock_api',
        'api_version': API_VERSION,
    }
    
    return record


@app.route('/')
def home():
    """API documentation endpoint."""
    return jsonify({
        'service': 'Mock Flight Data API',
        'version': API_VERSION,
        'description': 'Provides realistic flight data for reliability analysis',
        'endpoints': {
            '/': 'API documentation',
            '/health': 'Health check',
            '/api/v1/flights': 'Get flight data (GET)',
            '/api/v1/flights/realtime': 'Get real-time flight updates (GET)',
            '/api/v1/weather': 'Get weather observations (GET)',
            '/api/v1/stats': 'Get API statistics (GET)',
        },
        'parameters': {
            'limit': 'Number of records to return (default: random 200-300, max: 1000)',
            'date': 'Filter by date (YYYY-MM-DD)',
            'carrier': 'Filter by carrier code (e.g., AA, DL, UA)',
            'origin': 'Filter by origin airport code',
            'destination': 'Filter by destination airport code',
            'status': 'Filter by status (SCHEDULED, DEPARTED, ARRIVED, DELAYED, CANCELLED)',
        },
        'weather_parameters': {
            'airport': 'Filter by airport code (e.g., ORD, ATL, LAX)',
            'limit': 'Number of weather observations to return (default: 20, max: 100)',
        },
        'business_focus': {
            'goal': 'Optimize Flight Reliability for improved travel satisfaction',
            'metrics': [
                'On-time performance rates',
                'Delay patterns and causes',
                'Carrier reliability scores',
                'Cascade risk indicators',
                'Traveler-facing reliability bands',
            ],
        },
    })


@app.route('/health')
def health():
    """Health check endpoint for ECS/load balancers."""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'version': API_VERSION,
    })


@app.route(f'/api/{API_VERSION}/flights', methods=['GET'])
def get_flights():
    """
    Main endpoint for flight data retrieval.
    Supports filtering by various parameters.
    """
    # Parse query parameters
    limit = min(int(request.args.get('limit', ROWS_PER_REQUEST)), 1000)
    date_filter = request.args.get('date')  # YYYY-MM-DD
    carrier_filter = request.args.get('carrier', '').upper()
    origin_filter = request.args.get('origin', '').upper()
    destination_filter = request.args.get('destination', '').upper()
    status_filter = request.args.get('status', '').upper()
    
    # Determine base timestamp
    if date_filter:
        try:
            timestamp_base = datetime.strptime(date_filter, '%Y-%m-%d')
        except ValueError:
            return jsonify({'error': 'Invalid date format. Use YYYY-MM-DD'}), 400
    else:
        timestamp_base = datetime.utcnow()
    
    # Generate flight records
    flights = []
    attempts = 0
    max_attempts = limit * 3  # Prevent infinite loops with filters
    
    while len(flights) < limit and attempts < max_attempts:
        record = generate_flight_record(timestamp_base)
        attempts += 1
        
        # Apply filters
        if carrier_filter and record['carrier_code'] != carrier_filter:
            continue
        if origin_filter and record['origin_airport'] != origin_filter:
            continue
        if destination_filter and record['destination_airport'] != destination_filter:
            continue
        if status_filter and record['status'] != status_filter:
            continue
        
        flights.append(record)
    
    # Calculate summary statistics
    total_flights = len(flights)
    delayed_flights = sum(1 for f in flights if f['is_delayed'])
    cancelled_flights = sum(1 for f in flights if f['is_cancelled'])
    on_time_flights = sum(1 for f in flights if f['on_time'])
    
    on_time_rate = (on_time_flights / total_flights * 100) if total_flights > 0 else 0
    delay_rate = (delayed_flights / total_flights * 100) if total_flights > 0 else 0
    cancellation_rate = (cancelled_flights / total_flights * 100) if total_flights > 0 else 0
    
    avg_delay = sum(f['arrival_delay_minutes'] for f in flights 
                   if f['arrival_delay_minutes'] is not None) / max(delayed_flights, 1)
    
    return jsonify({
        'metadata': {
            'total_records': total_flights,
            'timestamp': datetime.utcnow().isoformat(),
            'date_filter': date_filter or timestamp_base.strftime('%Y-%m-%d'),
            'api_version': API_VERSION,
        },
        'summary_statistics': {
            'on_time_rate': round(on_time_rate, 2),
            'delay_rate': round(delay_rate, 2),
            'cancellation_rate': round(cancellation_rate, 2),
            'average_delay_minutes': round(avg_delay, 2),
            'total_flights': total_flights,
            'on_time_flights': on_time_flights,
            'delayed_flights': delayed_flights,
            'cancelled_flights': cancelled_flights,
        },
        'flights': flights,
    })


@app.route(f'/api/{API_VERSION}/flights/realtime', methods=['GET'])
def get_realtime_flights():
    """
    Real-time flight updates endpoint.
    Returns flights within current 15-minute window (matching EventBridge trigger).
    Optimized for fast generation - no filtering needed.
    Generates random 200-300 records by default.
    """
    # Random record count between 200-300 if not specified
    default_limit = random.randint(200, 300)
    limit = min(int(request.args.get('limit', default_limit)), 1000)
    
    # Get flights for current 15-minute window (matching EventBridge schedule)
    now = datetime.utcnow()
    flights = []
    
    # Generate flights directly within the 15-minute window (much faster!)
    for _ in range(limit):
        record = generate_flight_record(now, time_window_minutes=15)
        flights.append(record)
    
    return jsonify({
        'metadata': {
            'total_records': len(flights),
            'timestamp': now.isoformat(),
            'window_minutes': 15,
            'api_version': API_VERSION,
        },
        'flights': flights,
    })


@app.route(f'/api/{API_VERSION}/stats', methods=['GET'])
def get_stats():
    """
    API statistics and health metrics.
    Useful for monitoring scraper performance.
    """
    return jsonify({
        'api_info': {
            'version': API_VERSION,
            'uptime_status': 'running',
            'timestamp': datetime.utcnow().isoformat(),
        },
        'data_metrics': {
            'carriers_available': len(CARRIERS),
            'airports_available': len(AIRPORTS),
            'delay_reasons': len(DELAY_REASONS),
            'weather_phrases_available': len(WEATHER_PHRASES),
            'default_rows_per_request': ROWS_PER_REQUEST,
            'max_rows_per_request': 1000,
        },
        'carrier_reliability': [
            {
                'code': c['code'],
                'name': c['name'],
                'reliability_score': c['reliability_score']
            } for c in sorted(CARRIERS, key=lambda x: x['reliability_score'], reverse=True)
        ],
    })


@app.route(f'/api/{API_VERSION}/weather', methods=['GET'])
def get_weather():
    """
    Weather observations endpoint.
    Returns current weather data for airports with optional filtering.
    """
    # Parse query parameters
    limit = min(int(request.args.get('limit', 20)), 100)
    airport_filter = request.args.get('airport', '').upper()
    
    # Determine which airports to generate weather for
    if airport_filter:
        # Filter to specific airport
        airports_to_use = [a for a in AIRPORTS if a['code'] == airport_filter]
        if not airports_to_use:
            return jsonify({'error': f'Invalid airport code: {airport_filter}'}), 400
    else:
        # Use all airports
        airports_to_use = AIRPORTS
    
    # Generate weather observations
    weather_observations = []
    now = datetime.utcnow()
    
    # Generate multiple observations per airport if limit allows
    observations_per_airport = max(1, limit // len(airports_to_use))
    
    for airport in airports_to_use:
        for i in range(observations_per_airport):
            # Generate observations at different times (hourly intervals going back)
            observation_time = now - timedelta(hours=i)
            record = generate_weather_record(
                airport['code'],
                airport['city'],
                observation_time
            )
            weather_observations.append(record)
            
            if len(weather_observations) >= limit:
                break
        
        if len(weather_observations) >= limit:
            break
    
    # Calculate summary statistics
    total_observations = len(weather_observations)
    avg_temp = sum(w['temp'] for w in weather_observations) / max(total_observations, 1)
    avg_wspd = sum(w['wspd'] for w in weather_observations) / max(total_observations, 1)
    avg_vis = sum(w['vis'] for w in weather_observations) / max(total_observations, 1)
    
    # Count weather conditions
    weather_counts = {}
    for obs in weather_observations:
        phrase = obs['wx_phrase']
        weather_counts[phrase] = weather_counts.get(phrase, 0) + 1
    
    return jsonify({
        'metadata': {
            'total_observations': total_observations,
            'timestamp': now.isoformat(),
            'airport_filter': airport_filter if airport_filter else 'all',
            'api_version': API_VERSION,
        },
        'summary_statistics': {
            'average_temperature_f': round(avg_temp, 1),
            'average_wind_speed_mph': round(avg_wspd, 1),
            'average_visibility_miles': round(avg_vis, 2),
            'weather_conditions': weather_counts,
        },
        'observations': weather_observations,
    })


@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors."""
    return jsonify({
        'error': 'Endpoint not found',
        'message': 'The requested endpoint does not exist',
        'available_endpoints': [
            '/',
            '/health',
            f'/api/{API_VERSION}/flights',
            f'/api/{API_VERSION}/flights/realtime',
            f'/api/{API_VERSION}/weather',
            f'/api/{API_VERSION}/stats',
        ]
    }), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors."""
    return jsonify({
        'error': 'Internal server error',
        'message': 'An unexpected error occurred',
        'timestamp': datetime.utcnow().isoformat(),
    }), 500


if __name__ == '__main__':
    port = int(os.getenv('PORT', 5200))
    debug = os.getenv('DEBUG', 'False').lower() == 'true'
    
    print(f"Starting Mock Flight Data API on port {port}")
    print(f"API Version: {API_VERSION}")
    print(f"Default rows per request: {ROWS_PER_REQUEST}")
    print(f"Debug mode: {debug}")
    
    app.run(host='0.0.0.0', port=port, debug=debug)
