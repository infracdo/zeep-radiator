from dotenv import load_dotenv
from kafka import KafkaProducer
from kafka.errors import KafkaError
import redis.asyncio as redis

import json
import logging
import asyncio
import signal
import os
import re

load_dotenv()

REDIS_URL = os.getenv("REDIS_URL")
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD")
KAFKA_URL = os.getenv("KAFKA_URL")
KAFKA_CLIENT_ID = os.getenv("KAFKA_CLIENT_ID")
KAFKA_TIMEOUT = int(os.getenv("KAFKA_TIMEOUT", "30"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

producer = None
line_count = 0

def sanitize_topic_name(topic: str) -> str:
    # Trim whitespace
    topic = topic.strip()

    # Replace invalid characters with underscore
    # Allowed chars: a-zA-Z0-9 . _ -
    sanitized = re.sub(r'[^a-zA-Z0-9._-]', '_', topic)

    # Kafka topic max length is 249 characters
    return sanitized[:249]


async def send_to_kafka(producer, topic, jsondata):
    global line_count
    kafka_topic = sanitize_topic_name(topic)
    logging.info(f"Job data: {jsondata}")
    try:
        future = producer.send(kafka_topic, value=jsondata)
        line_count += 1
        metadata = await asyncio.to_thread(future.get, timeout=10)
        logging.info(f"Sent message to Kafka topic '{metadata.topic}', partition {metadata.partition}, offset {metadata.offset}")
        producer.flush()
        logging.info(f"Sent {line_count} total messages to Kafka topic '{kafka_topic}'")
    except KafkaError as e:
        logging.error(f"Kafka error: {e}")
    except Exception as e:
        logging.error(f"Unexpected error: {e}")

async def listen_to_topic(r, topic):
    logging.info(f"Listening to Redis topic '{topic}'")
    try:
        while True:
            job = await r.brpop(topic, timeout=1)
            if job:
                _, data = job
                if isinstance(data, bytes):
                    data = data.decode()
                try:
                    job_data = json.loads(data)
                    await send_to_kafka(producer, topic, job_data)
                except json.JSONDecodeError:
                    logging.error(f"Invalid job format: {data}")
                except Exception as e:
                    logging.error(f"Error processing job: {e}")
    except asyncio.CancelledError:
        logging.info(f"Listener for topic '{topic}' cancelled.")


async def main():
    global producer
    logging.info("Starting worker...")

    # Connect to Redis
    try:
        r = redis.Redis.from_url(
            url=REDIS_URL,
            password=REDIS_PASSWORD,
            decode_responses=False  # set False to receive bytes so we decode manually
        )
        logging.info(f"Connected to Redis {REDIS_URL}. Waiting for jobs... (Press Ctrl+C to stop gracefully)")
    except Exception as e:
        logging.error(f"Redis connection error: {e}")
        return

    # Initialize Kafka producer
    try:
        producer = KafkaProducer(
            bootstrap_servers=KAFKA_URL,
            client_id=KAFKA_CLIENT_ID,
            request_timeout_ms=KAFKA_TIMEOUT * 1000,
            value_serializer=lambda v: json.dumps(v).encode('utf-8')
        )
        logging.info(f"Kafka producer initialized (client_id={KAFKA_CLIENT_ID})")
    except Exception as e:
        logging.error(f"Failed to initialize Kafka producer: {e}")
        return

    # Get topics to listen on from .env
    topics_str = os.getenv("REDIS_TOPICS", "")
    topics = [topic.strip() for topic in topics_str.split(",") if topic.strip()]

    # Create a task for each topic listener
    tasks = [asyncio.create_task(listen_to_topic(r, topic)) for topic in topics]

    # Graceful shutdown setup
    running = True

    def signal_handler(signum, frame):
        nonlocal running
        logging.info("\nReceived shutdown signal. Stopping listeners gracefully...")
        running = False
        for task in tasks:
            task.cancel()

    signal.signal(signal.SIGINT, signal_handler)
    if hasattr(signal, 'SIGTERM'):
        signal.signal(signal.SIGTERM, signal_handler)

    try:
        while running:
            await asyncio.sleep(1)
    except asyncio.CancelledError:
        pass
    finally:
        logging.info("Shutting down...")
        for task in tasks:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

        try:
            logging.info("Closing Redis connection...")
            await r.aclose()
            logging.info("Redis connection closed.")
        except Exception as e:
            logging.warning(f"Error closing Redis: {e}")

        try:
            if producer:
                producer.flush()
                producer.close()
                logging.info("Kafka producer closed.")
        except Exception as e:
            logging.warning(f"Error closing Kafka producer: {e}")

        logging.info("Worker stopped.")

if __name__ == "__main__":
    asyncio.run(main())
