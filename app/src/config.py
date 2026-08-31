import json
import os

import boto3


def _fetch_secret(secret_name, region):
    """Fetch and JSON-parse a Secrets Manager secret. Returns {} on any
    failure (unset name, no network, no IAM permission) -- config values
    fall back to None/defaults rather than crashing the app at import."""
    if not secret_name:
        return {}
    try:
        client = boto3.client("secretsmanager", region_name=region)
        response = client.get_secret_value(SecretId=secret_name)
        return json.loads(response["SecretString"])
    except Exception:
        return {}


class Config:
    APP_PORT = int(os.environ.get("APP_PORT", "8000"))
    AWS_REGION = os.environ.get("AWS_REGION", "eu-central-1")

    _db_secret = _fetch_secret(os.environ.get("DB_SECRET_NAME"), AWS_REGION)
    DB_HOST = _db_secret.get("host") or os.environ.get("DB_HOST")
    DB_PORT = int(_db_secret.get("port") or os.environ.get("DB_PORT", "5432"))
    DB_NAME = _db_secret.get("dbname", "bouncer")
    DB_USER = _db_secret.get("username")
    DB_PASSWORD = _db_secret.get("password")
    DB_CHECK_TIMEOUT_SECONDS = float(os.environ.get("DB_CHECK_TIMEOUT_SECONDS", "2"))

    _cache_secret = _fetch_secret(os.environ.get("CACHE_SECRET_NAME"), AWS_REGION)
    CACHE_HOST = _cache_secret.get("host")
    CACHE_PORT = int(_cache_secret.get("port", 6379))
    CACHE_AUTH_TOKEN = _cache_secret.get("auth_token")
    CACHE_TLS = True  # transit_encryption_mode = "required" on the replication group

    SESSION_TTL_SECONDS = int(os.environ.get("SESSION_TTL_SECONDS", "1800"))
    # Defaults to false: the ALB only has an HTTP listener right now (no
    # ACM/Route53 yet), and a Secure cookie is silently dropped by clients
    # over plain HTTP. Flip to true (or set the env var) once HTTPS is live.
    SESSION_COOKIE_SECURE = os.environ.get("SESSION_COOKIE_SECURE", "false").lower() == "true"

    MAX_FAILED_LOGIN_ATTEMPTS = int(os.environ.get("MAX_FAILED_LOGIN_ATTEMPTS", "5"))
    LOCKOUT_DURATION_SECONDS = int(os.environ.get("LOCKOUT_DURATION_SECONDS", "300"))