from minio import Minio
import pandas as pd
import psycopg2
import io
from datetime import datetime
import schedule
import time

# === CONFIGURATION ===

# MinIO settings
MINIO_ENDPOINT = "192.168.32.24:9000"  # Replace with your MinIO endpoint
MINIO_ACCESS_KEY = "admin@minio.com.ph"           # Replace with your MinIO access key
MINIO_SECRET_KEY = "ap0ll02k25"           # Replace with your MinIO secret key
BUCKET_NAME = "openobserve"
METRIC_PREFIX = "files/default/metrics/container_cpu_usage_seconds_total/"

# PostgreSQL settings
PG_HOST = "localhost"
PG_DB = "radius"
PG_USER = "radiator"
PG_PASSWORD = "ap0ll0ap0ll0"               # Replace with your actual password

# === CONNECTION SETUP ===

# Connect to MinIO
minio_client = Minio(
    MINIO_ENDPOINT,
    access_key=MINIO_ACCESS_KEY,
    secret_key=MINIO_SECRET_KEY,
    secure=False  # Set to True if using HTTPS
)

# Connect to PostgreSQL
pg_conn = psycopg2.connect(
    host=PG_HOST,
    dbname=PG_DB,
    user=PG_USER,
    password=PG_PASSWORD
)
pg_cursor = pg_conn.cursor()

# === ETL FUNCTION ===

def process_latest_parquet_file():
    print(f"🔍 Scanning {METRIC_PREFIX} for the latest Parquet file...")
    latest_obj = None
    latest_time = None

    # Find the most recently modified Parquet file
    for obj in minio_client.list_objects(BUCKET_NAME, prefix=METRIC_PREFIX, recursive=True):
        if not obj.object_name.endswith(".parquet"):
            continue
        if latest_time is None or obj.last_modified > latest_time:
            latest_obj = obj
            latest_time = obj.last_modified

    if not latest_obj:
        print("⚠️ No Parquet files found.")
        return

    print(f"📦 Latest file: {latest_obj.object_name} (Last modified: {latest_time})")

    try:
        response = minio_client.get_object(BUCKET_NAME, latest_obj.object_name)
        parquet_bytes = io.BytesIO(response.read())
        df = pd.read_parquet(parquet_bytes)

        for _, row in df.iterrows():
            ts_micro = row.get("__timestamp")
            ts = datetime.utcfromtimestamp(ts_micro / 1_000_000) if ts_micro else None

            metric_name = row.get("__name__", "unknown")
            value = row.get("value", None)
            namespace = row.get("namespace", "unknown")
            pod = row.get("pod", "unknown")
            container = row.get("container", "unknown")
            node = row.get("node", "unknown")
            instance = row.get("instance", "unknown")
            job = row.get("job", "unknown")

            pg_cursor.execute("""
                INSERT INTO metrics (
                    timestamp, metric_name, value,
                    namespace, pod, container,
                    node, instance, job
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (ts, metric_name, value, namespace, pod, container, node, instance, job))

        pg_conn.commit()
        print("✅ Ingested latest metrics file successfully.")

    except Exception as e:
        print(f"❌ Error processing file: {e}")

# === SCHEDULER ===

# Run once now (or comment this out if you only want scheduled runs)
process_latest_parquet_file()

# Schedule to run every day at 16:10
schedule.every().day.at("16:10").do(process_latest_parquet_file)

print("⏳ Waiting for scheduled ETL run...")
while True:
    schedule.run_pending()
    time.sleep(60)
