from minio import Minio
from io import BytesIO
import pandas as pd
from datetime import datetime
import psycopg2

# --- CONFIGURATION ---
MINIO_ENDPOINT = "192.168.32.27:9000"
MINIO_ACCESS_KEY = "admin@minio.com.ph"
MINIO_SECRET_KEY = "ap0ll02k25"
BUCKET_NAME = "openobserve"
PARQUET_PREFIX = "files/default/metrics/kube_pod_container_resource_limits/"

PG_HOST = "localhost"
PG_DB = "radius"
PG_USER = "radiator"
PG_PASSWORD = "ap0ll0ap0ll0"

# --- CONNECT TO MINIO ---
minio_client = Minio(
    MINIO_ENDPOINT,
    access_key=MINIO_ACCESS_KEY,
    secret_key=MINIO_SECRET_KEY,
    secure=False
)

# === FUNCTIONS ===

def get_latest_parquet_file():
    objects = list(minio_client.list_objects(BUCKET_NAME, prefix=PARQUET_PREFIX, recursive=True))
    parquet_files = sorted(
        [obj for obj in objects if obj.object_name.endswith(".parquet")],
        key=lambda x: x.last_modified
    )
    return parquet_files[-1] if parquet_files else None

def read_parquet_from_minio(obj):
    response = minio_client.get_object(BUCKET_NAME, obj.object_name)
    data = response.read()
    return pd.read_parquet(BytesIO(data), engine="pyarrow")

def extract_pod_resource_values(df, timestamp):
    df_filtered = df[df["resource"].isin(["cpu", "memory"])]
    df_final = df_filtered[["namespace", "pod", "resource", "value"]].copy()
    df_final["collected_at"] = timestamp.date()
    return df_final

def insert_to_postgres(df):
    try:
        conn = psycopg2.connect(
            host=PG_HOST,
            dbname=PG_DB,
            user=PG_USER,
            password=PG_PASSWORD
        )
        cursor = conn.cursor()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS pod_resource_usage_limits (
                id SERIAL PRIMARY KEY,
                namespace TEXT NOT NULL,
                pod TEXT NOT NULL,
                resource TEXT NOT NULL,
                value DOUBLE PRECISION NOT NULL,
                collected_at DATE NOT NULL,
                UNIQUE(namespace, pod, resource, collected_at)
            );
        """)

        for _, row in df.iterrows():
            cursor.execute("""
                INSERT INTO pod_resource_usage_limits (namespace, pod, resource, value, collected_at)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (namespace, pod, resource, collected_at) DO UPDATE
                SET value = EXCLUDED.value;
            """, (row["namespace"], row["pod"], row["resource"], row["value"], row["collected_at"]))

        conn.commit()
        cursor.close()
        conn.close()
        print("✅ Pod resource values inserted into PostgreSQL.")
    except Exception as e:
        print(f"❌ PostgreSQL error: {e}")

# === MAIN EXECUTION ===

if __name__ == "__main__":
    print(f"🔍 Scanning {PARQUET_PREFIX} for latest .parquet file...")
    parquet_file = get_latest_parquet_file()

    if not parquet_file:
        print("❌ No .parquet files found.")
        exit(1)

    timestamp = parquet_file.last_modified
    print(f"📦 Latest file: {parquet_file.object_name} ({timestamp})")

    df = read_parquet_from_minio(parquet_file)
    df_resources = extract_pod_resource_values(df, timestamp)

    print("\n🧾 Extracted resource usage per pod:")
    print(df_resources)

    insert_to_postgres(df_resources)
