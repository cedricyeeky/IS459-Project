#!/bin/bash

# Quick start script for Mock Flight Data API
# This script helps you quickly start the API in different modes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        echo "Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    print_success "Docker is installed"
}

# Check if Docker Compose is installed
check_docker_compose() {
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed"
        echo "Please install Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
    print_success "Docker Compose is installed"
}

# Start with Docker Compose
start_docker_compose() {
    print_header "Starting Mock API with Docker Compose"
    
    check_docker
    check_docker_compose
    
    echo "Building and starting containers..."
    docker-compose up -d --build
    
    echo ""
    print_success "API is starting up..."
    echo ""
    echo "Waiting for API to be ready..."
    sleep 5
    
    # Check if API is healthy
    if curl -f http://localhost:5000/health > /dev/null 2>&1; then
        print_success "API is healthy and ready!"
        echo ""
        echo "API URL: http://localhost:5000"
        echo "Documentation: http://localhost:5000/"
        echo ""
        echo "View logs: docker-compose logs -f"
        echo "Stop API: docker-compose down"
    else
        print_warning "API is starting but not yet responding"
        echo "Check logs with: docker-compose logs -f"
    fi
}

# Start with local Python
start_local() {
    print_header "Starting Mock API Locally"
    
    # Check if Python is installed
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed"
        exit 1
    fi
    print_success "Python 3 is installed"
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        echo "Creating virtual environment..."
        python3 -m venv venv
        print_success "Virtual environment created"
    fi
    
    # Activate virtual environment
    echo "Activating virtual environment..."
    source venv/bin/activate
    
    # Install dependencies
    echo "Installing dependencies..."
    pip install -q -r requirements.txt
    print_success "Dependencies installed"
    
    # Copy env file if it doesn't exist
    if [ ! -f ".env" ]; then
        cp .env.example .env
        print_success "Created .env file"
    fi
    
    # Start the API
    echo ""
    print_success "Starting API..."
    echo ""
    python app.py
}

# Run tests
run_tests() {
    print_header "Running API Tests"
    
    # Check if API is running
    if ! curl -f http://localhost:5000/health > /dev/null 2>&1; then
        print_error "API is not running"
        echo "Start the API first with: ./start.sh docker"
        exit 1
    fi
    
    print_success "API is running"
    echo ""
    
    # Check if requests is installed
    if ! python3 -c "import requests" 2>/dev/null; then
        echo "Installing requests..."
        pip install -q requests
    fi
    
    # Run tests
    python3 test_api.py
}

# Stop Docker Compose
stop_docker() {
    print_header "Stopping Mock API"
    
    docker-compose down
    print_success "API stopped"
}

# Show logs
show_logs() {
    print_header "API Logs"
    
    if docker-compose ps | grep -q "Up"; then
        docker-compose logs -f
    else
        print_error "API is not running"
    fi
}

# Show help
show_help() {
    echo "Mock Flight Data API - Quick Start Script"
    echo ""
    echo "Usage: ./start.sh [command]"
    echo ""
    echo "Commands:"
    echo "  docker      Start API with Docker Compose (recommended)"
    echo "  local       Start API locally with Python"
    echo "  test        Run API tests"
    echo "  stop        Stop Docker containers"
    echo "  logs        Show API logs"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./start.sh docker    # Start with Docker"
    echo "  ./start.sh test      # Run tests"
    echo "  ./start.sh logs      # View logs"
    echo "  ./start.sh stop      # Stop API"
    echo ""
}

# Main script
case "${1:-docker}" in
    docker)
        start_docker_compose
        ;;
    local)
        start_local
        ;;
    test)
        run_tests
        ;;
    stop)
        stop_docker
        ;;
    logs)
        show_logs
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
