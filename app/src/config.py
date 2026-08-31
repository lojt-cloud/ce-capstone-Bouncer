import os


class Config:
    APP_PORT = int(os.environ.get("APP_PORT", "8000"))
    # Unset until the data-tier module provisions RDS and wires this in.
    DB_HOST = os.environ.get("DB_HOST")
    DB_PORT = int(os.environ.get("DB_PORT", "5432"))
    DB_CHECK_TIMEOUT_SECONDS = float(os.environ.get("DB_CHECK_TIMEOUT_SECONDS", "2"))