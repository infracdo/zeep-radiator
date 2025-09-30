FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy script
COPY redis_kafka_worker.py .

CMD ["python", "redis_kafka_worker.py"]
