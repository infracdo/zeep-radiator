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

# Parquet Prefixes
PARQUET_PREFIX_REQUESTS = "files/default/metrics/kube_persistentvolumeclaim_resource_requests_storage_bytes/"
PARQUET_PREFIX_USAGE = "files/default/metrics/kubelet_volume_stats_used_bytes/"

# PostgreSQL Settings
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

# --- FUNCTIONS ---
def get_latest_parquet_file(prefix):
    objects = list(minio_client.list_objects(BUCKET_NAME, prefix=prefix, recursive=True))
    parquet_files = sorted(
        [obj for obj in objects if obj.object_name.endswith(".parquet")],
        key=lambda x: x.last_modified
    )
    return parquet_files[-1] if parquet_files else None

def read_parquet_from_minio(obj):
    response = minio_client.get_object(BUCKET_NAME, obj.object_name)
    data = response.read()
    return pd.read_parquet(BytesIO(data), engine="pyarrow")

def extract_pvc_data(df, timestamp):
    try:
        df_filtered = df[["namespace", "persistentvolumeclaim", "value"]].dropna()
        df_filtered["collected_at"] = timestamp
        return df_filtered
    except KeyError as e:
        print(f"❌ Missing expected column: {e}")
        return pd.DataFrame()

def find_unused_pvcs(df_requests, df_usage):
    used_keys = set(zip(df_usage["namespace"], df_usage["persistentvolumeclaim"]))
    req_keys = set(zip(df_requests["namespace"], df_requests["persistentvolumeclaim"]))

    unused_keys = req_keys - used_keys

    unused_df = df_requests[
        df_requests.apply(lambda row: (row["namespace"], row["persistentvolumeclaim"]) in unused_keys, axis=1)
    ].reset_index(drop=True)

    return unused_df

def insert_unused_pvcs_to_postgres(df):
    if df.empty:
        print("⚠️ No unused PVCs to insert.")
        return

    try:
        conn = psycopg2.connect(
            host=PG_HOST,
            dbname=PG_DB,
            user=PG_USER,
            password=PG_PASSWORD
        )
        cursor = conn.cursor()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS unused_pvc_storage_requests (
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
                INSERT INTO unused_pvc_storage_requests (namespace, persistentvolumeclaim, value, collected_at)
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
        print("✅ Unused PVCs inserted into PostgreSQL.")
    except Exception as e:
        print(f"❌ PostgreSQL error: {e}")

# --- MAIN ---
if __name__ == "__main__":
    print("🔍 Checking for unused PVCs...")

    req_file = get_latest_parquet_file(PARQUET_PREFIX_REQUESTS)
    use_file = get_latest_parquet_file(PARQUET_PREFIX_USAGE)

    if not req_file or not use_file:
        print("❌ One or both required .parquet files not found.")
        exit(1)

    ts = req_file.last_modified  # Use the timestamp of the request file for tracking

    print(f"📦 Request file: {req_file.object_name} ({ts})")
    print(f"📦 Usage file:   {use_file.object_name} ({use_file.last_modified})")

    df_req = read_parquet_from_minio(req_file)
    df_use = read_parquet_from_minio(use_file)

    df_req_filtered = extract_pvc_data(df_req, ts)
    df_use_filtered = extract_pvc_data(df_use, ts)

    unused_df = find_unused_pvcs(df_req_filtered, df_use_filtered)

    print("\n🧾 PVCs with storage requests but no current usage:")
    print(unused_df[["namespace", "persistentvolumeclaim", "value"]])

    insert_unused_pvcs_to_postgres(unused_df)
