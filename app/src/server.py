import socket
import urllib.request

from flask import Flask, jsonify, render_template

from config import Config

app = Flask(__name__)

IMDS_TOKEN_URL = "http://169.254.169.254/latest/api/token"
IMDS_META_URL = "http://169.254.169.254/latest/meta-data/{}"


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


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=Config.APP_PORT)