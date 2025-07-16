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

PVC_REQUEST_PREFIX = "files/default/metrics/kube_persistentvolumeclaim_resource_requests_storage_bytes/"
PVC_POD_MAP_PREFIX = "files/default/metrics/kube_pod_spec_volumes_persistentvolumeclaims_info/"

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

def get_latest_parquet_file(prefix):
    objects = list(minio_client.list_objects(BUCKET_NAME, prefix=prefix, recursive=True))
    parquet_files = sorted(
        [obj for obj in objects if obj.object_name.endswith(".parquet")],
        key=lambda x: x.last_modified
    )
    return parquet_files[-1] if parquet_files else None

def read_parquet_from_minio(obj, columns):
    response = minio_client.get_object(BUCKET_NAME, obj.object_name)
    data = response.read()
    return pd.read_parquet(BytesIO(data), engine="pyarrow", columns=columns)

def extract_pvc_requests(df, timestamp):
    df_filtered = df.dropna(subset=["namespace", "persistentvolumeclaim", "value"])
    df_filtered["collected_at"] = timestamp
    return df_filtered

def extract_pvc_pod_mappings(df):
    return df.dropna(subset=["namespace", "persistentvolumeclaim", "pod"])

def insert_to_postgres(df):
    if df.empty:
        print("⚠️ No data to insert.")
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
            CREATE TABLE IF NOT EXISTS pvc_storage_requests_with_pod (
                id SERIAL PRIMARY KEY,
                namespace TEXT,
                persistentvolumeclaim TEXT,
                value BIGINT,
                pod TEXT,
                collected_at TIMESTAMPTZ,
                UNIQUE(namespace, persistentvolumeclaim, collected_at)
            );
        """)

        for _, row in df.iterrows():
            cursor.execute("""
                INSERT INTO pvc_storage_requests_with_pod (namespace, persistentvolumeclaim, value, pod, collected_at)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (namespace, persistentvolumeclaim, collected_at) DO NOTHING;
            """, (
                row["namespace"],
                row["persistentvolumeclaim"],
                int(row["value"]),
                row.get("pod", None),
                row["collected_at"]
            ))

        conn.commit()
        cursor.close()
        conn.close()
        print("✅ PVC storage requests with pod info inserted into PostgreSQL.")
    except Exception as e:
        print(f"❌ PostgreSQL error: {e}")

# === MAIN EXECUTION ===

if __name__ == "__main__":
    print("🔍 Scanning for latest PVC requests...")
    pvc_file = get_latest_parquet_file(PVC_REQUEST_PREFIX)

    print("🔍 Scanning for latest PVC-pod mapping info...")
    pod_file = get_latest_parquet_file(PVC_POD_MAP_PREFIX)

    if not pvc_file or not pod_file:
        print("❌ Required .parquet files not found.")
        exit(1)

    print(f"📦 PVC requests file: {pvc_file.object_name} ({pvc_file.last_modified})")
    print(f"📦 PVC-pod map file: {pod_file.object_name}")

    df_pvc = read_parquet_from_minio(pvc_file, ["namespace", "persistentvolumeclaim", "value"])
    df_pods = read_parquet_from_minio(pod_file, ["namespace", "persistentvolumeclaim", "pod"])

    df_pvc = extract_pvc_requests(df_pvc, pvc_file.last_modified)
    df_pods = extract_pvc_pod_mappings(df_pods)

    # Merge PVC info with pod info (left join)
    df_merged = pd.merge(
        df_pvc,
        df_pods,
        on=["namespace", "persistentvolumeclaim"],
        how="left"
    )

    df_merged["pod"] = df_merged["pod"].fillna("UNUSED")

    print("\n🧾 PVC storage requests with pod mapping:")
    print(df_merged)

    insert_to_postgres(df_merged)
