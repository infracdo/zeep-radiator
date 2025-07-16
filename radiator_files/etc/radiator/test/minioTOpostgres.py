from minio import Minio
from minio.error import S3Error
import os
import pandas as pd
from datetime import timezone
import pyarrow.parquet as pq
from io import BytesIO
import pyarrow
import psycopg2
from datetime import datetime

# --- CONFIGURATION ---
MINIO_ENDPOINT = "192.168.32.24:9000"  # Replace with your MinIO endpoint
MINIO_ACCESS_KEY = "admin@minio.com.ph"           # Replace with your MinIO access key
MINIO_SECRET_KEY = "ap0ll02k25"           # Replace with your MinIO secret key
BUCKET_NAME = "openobserve"
PARQUET_PREFIX = "files/default/metrics/container_cpu_usage_seconds_total/"

# PostgreSQL settings
PG_HOST = "localhost"
PG_DB = "radius"
PG_USER = "radiator"
PG_PASSWORD = "ap0ll0ap0ll0"

# --- CONNECT TO MINIO ---
minio_client = Minio(
    MINIO_ENDPOINT,
    access_key=MINIO_ACCESS_KEY,
    secret_key=MINIO_SECRET_KEY,
    secure=False  # Set to True if using HTTPS
)

# === FUNCTIONS ===

def get_latest_two_parquet_files():
    objects = list(minio_client.list_objects(BUCKET_NAME, prefix=PARQUET_PREFIX, recursive=True))
    parquet_files = sorted([obj for obj in objects if obj.object_name.endswith(".parquet")], key=lambda x: x.last_modified)
    return parquet_files[-2:]

def read_parquet_from_minio(obj):
    response = minio_client.get_object(BUCKET_NAME, obj.object_name)
    data = response.read()
    return pd.read_parquet(BytesIO(data), engine='pyarrow')

def compute_namespace_usage_rate(df_prev, df_latest, ts_prev, ts_latest):
    df_prev = df_prev[["namespace", "value"]].groupby("namespace").sum().rename(columns={"value": "prev_value"})
    df_latest = df_latest[["namespace", "value"]].groupby("namespace").sum().rename(columns={"value": "latest_value"})

    df_combined = df_prev.join(df_latest, how="inner")
    time_diff = (ts_latest - ts_prev).total_seconds()

    df_combined["usage_rate"] = (df_combined["latest_value"] - df_combined["prev_value"]) / time_diff
    df_combined["collected_at"] = ts_latest
    return df_combined.reset_index()[["namespace", "usage_rate", "collected_at"]]

def insert_usage_to_postgres(df):
    try:
        conn = psycopg2.connect(
            host=PG_HOST,
            dbname=PG_DB,
            user=PG_USER,
            password=PG_PASSWORD
        )
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS namespace_cpu_usage_rate (
                id SERIAL PRIMARY KEY,
                namespace TEXT,
                usage_rate DOUBLE PRECISION,
                collected_at TIMESTAMPTZ
            );
        """)
        for _, row in df.iterrows():
            cursor.execute("""
                INSERT INTO namespace_cpu_usage_rate (namespace, usage_rate, collected_at)
                VALUES (%s, %s, %s)
            """, (row["namespace"], row["usage_rate"], row["collected_at"]))
        conn.commit()
        cursor.close()
        conn.close()
        print("✅ Data inserted into PostgreSQL.")
    except Exception as e:
        print(f"❌ PostgreSQL error: {e}")

# === MAIN EXECUTION ===

if __name__ == "__main__":
    print(f"🔍 Scanning {PARQUET_PREFIX} for latest .parquet files...")
    parquet_files = get_latest_two_parquet_files()

    if len(parquet_files) < 2:
        print("❌ Not enough .parquet files found.")
        exit(1)

    file1, file2 = parquet_files[-2], parquet_files[-1]
    ts1, ts2 = file1.last_modified, file2.last_modified

    print(f"📦 Previous file: {file1.object_name} ({ts1})")
    print(f"📦 Latest file:   {file2.object_name} ({ts2})")

    df1 = read_parquet_from_minio(file1)
    df2 = read_parquet_from_minio(file2)

    df_usage = compute_namespace_usage_rate(df1, df2, ts1, ts2)

    print("\n🧾 Computed CPU usage (cores used per second):")
    print(df_usage)

    insert_usage_to_postgres(df_usage)