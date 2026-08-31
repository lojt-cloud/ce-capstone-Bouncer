import json
import os
import secrets
import socket
import time
import urllib.request


import bcrypt
import psycopg
import redis
from flask import Flask, jsonify, make_response, render_template, request
from psycopg_pool import ConnectionPool

from config import Config

app = Flask(__name__)

IMDS_TOKEN_URL = "http://169.254.169.254/latest/api/token"
IMDS_META_URL = "http://169.254.169.254/latest/meta-data/{}"

# Fixed bcrypt hash checked against when a username doesn't exist, so a
# failed login for an unknown user takes roughly the same time as a wrong
# password for a real one -- avoids leaking which usernames are registered
# via response timing.
_DUMMY_HASH = bcrypt.hashpw(b"dummy-password-for-timing-safety", bcrypt.gensalt()).decode()

_db_pool = None
if Config.DB_HOST and Config.DB_USER and Config.DB_PASSWORD:
    _db_pool = ConnectionPool(
        conninfo="",
        kwargs={
            "host": Config.DB_HOST,
            "port": Config.DB_PORT,
            "dbname": Config.DB_NAME,
            "user": Config.DB_USER,
            "password": Config.DB_PASSWORD,
        },
        min_size=1,
        max_size=5,
        open=False,
    )
    try:
        _db_pool.open(wait=True, timeout=Config.DB_CHECK_TIMEOUT_SECONDS)
    except psycopg.OperationalError:
        _db_pool.close()
        _db_pool = None

# Self-heals the schema: if RDS is ever destroyed and recreated (or this
# is a fresh environment), the app creates the users table itself on the
# first successful connection. CREATE TABLE IF NOT EXISTS is idempotent,
# so this is safe to run on every boot and from every gunicorn worker
# (-w 2 means this block runs twice at startup, by design).
if _db_pool is not None:
    _schema_path = os.path.join(os.path.dirname(__file__), "schema.sql")
    try:
        with open(_schema_path) as f:
            schema_sql = f.read()
        conn = _db_pool.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute(schema_sql)
            conn.commit()
        finally:
            _db_pool.putconn(conn)
    except Exception as exc:
        print(f"[schema init] failed to apply schema.sql: {exc}")

_redis_client = None
if Config.CACHE_HOST:
    _redis_client = redis.Redis(
        host=Config.CACHE_HOST,
        port=Config.CACHE_PORT,
        password=Config.CACHE_AUTH_TOKEN,
        ssl=Config.CACHE_TLS,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )

FAIL_KEY = "login:fail:{}"
LOCK_KEY = "login:lock:{}"
SESSION_KEY = "session:{}"


def get_imds_token():
    req = urllib.request.Request(
        IMDS_TOKEN_URL,
        method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
    )
    with urllib.request.urlopen(req, timeout=2) as resp:
        return resp.read().decode()


def get_metadata(path):
    # Falls through to "unknown" off-EC2 (e.g. running this locally) and
    # on any IMDS error -- the page should degrade, never crash, on this.
    try:
        token = get_imds_token()
        req = urllib.request.Request(
            IMDS_META_URL.format(path),
            headers={"X-aws-ec2-metadata-token": token},
        )
        with urllib.request.urlopen(req, timeout=2) as resp:
            return resp.read().decode()
    except Exception:
        return "unknown"


def check_db_status():
    """Single-AZ RDS is a deliberate cost trade-off for this project, not
    a capacity limitation -- Multi-AZ is documented as the production
    recommendation. See ARCHITECTURE.md / COSTS.md."""
    host = Config.DB_HOST
    if not host:
        return {"configured": False, "status": "not_provisioned"}
    try:
        with socket.create_connection(
            (host, Config.DB_PORT), timeout=Config.DB_CHECK_TIMEOUT_SECONDS
        ):
            return {"configured": True, "status": "connected", "host": host}
    except OSError:
        return {"configured": True, "status": "unreachable", "host": host}


def get_db_connection():
    if _db_pool is None:
        return None
    return _db_pool.getconn()


def release_db_connection(conn):
    if _db_pool is not None and conn is not None:
        _db_pool.putconn(conn)


def verify_credentials(username, password):
    conn = get_db_connection()
    if conn is None:
        raise RuntimeError("database not configured")
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT password_hash FROM users WHERE username = %s", (username,)
            )
            row = cur.fetchone()
    finally:
        release_db_connection(conn)

    stored_hash = row[0] if row else _DUMMY_HASH
    return bcrypt.checkpw(password.encode("utf-8"), stored_hash.encode("utf-8"))


@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200


@app.route("/")
def status():
    return render_template(
        "status.html",
        instance_id=get_metadata("instance-id"),
        az=get_metadata("placement/availability-zone"),
        db=check_db_status(),
    )


@app.route("/login", methods=["POST"])
def login():
    if _redis_client is None:
        return jsonify({"error": "cache tier not configured"}), 503

    data = request.get_json(silent=True) or request.form
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""
    if not username or not password:
        return jsonify({"error": "username and password required"}), 400

    lock_key = LOCK_KEY.format(username)
    try:
        ttl = _redis_client.ttl(lock_key)
    except redis.RedisError:
        return jsonify({"error": "cache tier unreachable"}), 503
    if ttl and ttl > 0:
        return jsonify({"error": "account locked", "retry_after_seconds": ttl}), 423

    try:
        valid = verify_credentials(username, password)
    except RuntimeError:
        return jsonify({"error": "database tier not configured"}), 503
    except psycopg.OperationalError:
        return jsonify({"error": "database tier error"}), 503

    fail_key = FAIL_KEY.format(username)
    if not valid:
        attempts = _redis_client.incr(fail_key)
        if attempts >= Config.MAX_FAILED_LOGIN_ATTEMPTS:
            _redis_client.setex(lock_key, Config.LOCKOUT_DURATION_SECONDS, 1)
            _redis_client.delete(fail_key)
        return jsonify({"error": "invalid credentials"}), 401

    _redis_client.delete(fail_key, lock_key)

    sid = secrets.token_urlsafe(32)
    _redis_client.setex(
        SESSION_KEY.format(sid),
        Config.SESSION_TTL_SECONDS,
        json.dumps({"username": username, "created_at": time.time()}),
    )

    resp = make_response(jsonify({"status": "ok", "username": username}))
    resp.set_cookie(
        "session_id",
        sid,
        max_age=Config.SESSION_TTL_SECONDS,
        httponly=True,
        secure=Config.SESSION_COOKIE_SECURE,
        samesite="Lax",
    )
    return resp


@app.route("/logout", methods=["POST"])
def logout():
    sid = request.cookies.get("session_id")
    if sid and _redis_client is not None:
        try:
            _redis_client.delete(SESSION_KEY.format(sid))
        except redis.RedisError:
            pass
    resp = make_response(jsonify({"status": "ok"}))
    resp.delete_cookie("session_id")
    return resp


@app.route("/me")
def me():
    sid = request.cookies.get("session_id")
    if not sid or _redis_client is None:
        return jsonify({"authenticated": False}), 401
    session_key = SESSION_KEY.format(sid)
    try:
        raw = _redis_client.get(session_key)
    except redis.RedisError:
        return jsonify({"error": "cache tier unreachable"}), 503
    if not raw:
        return jsonify({"authenticated": False}), 401
    _redis_client.expire(session_key, Config.SESSION_TTL_SECONDS)
    session_data = json.loads(raw)
    return jsonify({"authenticated": True, "username": session_data["username"]})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=Config.APP_PORT)