# Multi-stage build for Python scraper
FROM python:3.11-slim AS builder

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Create non-root user first
RUN useradd -m -u 1000 scraper

# Copy Python dependencies from builder to scraper's home
COPY --from=builder /root/.local /home/scraper/.local

# Copy application code
COPY app.py .

# Change ownership
RUN chown -R scraper:scraper /app /home/scraper/.local

# Make sure scripts in .local are usable
ENV PATH=/home/scraper/.local/bin:$PATH

# Switch to non-root user
USER scraper

# Health check (not really applicable for a one-shot scraper, but good practice)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python -c "import sys; sys.exit(0)"

# Run the scraper
CMD ["python", "-u", "app.py"]
