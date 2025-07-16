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
PARQUET_PREFIX = "files/default/metrics/kube_persistentvolumeclaim_resource_requests_storage_bytes/"

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

def extract_pvc_requests(df, timestamp):
    try:
        df_filtered = df[["namespace", "persistentvolumeclaim", "value"]].dropna()
    except KeyError as e:
        print(f"❌ Missing expected column in .parquet file: {e}")
        return pd.DataFrame()

    df_filtered["collected_at"] = timestamp
    return df_filtered

def insert_pvc_requests_to_postgres(df):
    if df.empty:
        print("⚠️  No valid PVC data to insert.")
        return

    try:
        conn = psycopg2.connect(
            host=PG_HOST,
            dbname=PG_DB,
            user=PG_USER,
            password=PG_PASSWORD
        )
        cursor = conn.cursor()

        # Create table with unique constraint
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS pvc_storage_requests (
                id SERIAL PRIMARY KEY,
                namespace TEXT,
                persistentvolumeclaim TEXT,
                value BIGINT,
                collected_at TIMESTAMPTZ,
                UNIQUE(namespace, persistentvolumeclaim, collected_at)
            );
        """)

        for _, row in df.iterrows():
            cursor.execute("""
                INSERT INTO pvc_storage_requests (namespace, persistentvolumeclaim, value, collected_at)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (namespace, persistentvolumeclaim, collected_at) DO NOTHING
            """, (
                row["namespace"],
                row["persistentvolumeclaim"],
                int(row["value"]),
                row["collected_at"]
            ))

        conn.commit()
        cursor.close()
        conn.close()
        print("✅ PVC storage requests inserted into PostgreSQL.")
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
    df_pvc = extract_pvc_requests(df, timestamp)

    print("\n🧾 Extracted PVC storage requests:")
    print(df_pvc)

    insert_pvc_requests_to_postgres(df_pvc)