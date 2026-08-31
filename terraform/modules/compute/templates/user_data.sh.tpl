#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

dnf update -y
dnf install -y python3-pip amazon-cloudwatch-agent unzip

APP_DIR="/opt/bouncer-app"
mkdir -p "$APP_DIR"

aws s3 cp "s3://${app_bucket}/${app_artifact_key}" /tmp/app.zip --region ${aws_region}
unzip -o /tmp/app.zip -d "$APP_DIR"

cd "$APP_DIR"
python3 -m venv venv
source venv/bin/activate
pip install --no-cache-dir -r requirements.txt

cat > /etc/systemd/system/bouncer-app.service <<'UNIT'
[Unit]
Description=Bouncer Flask App
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/bouncer-app
Environment=PYTHONUNBUFFERED=1
Environment=APP_PORT=${app_port}
ExecStart=/opt/bouncer-app/venv/bin/gunicorn -w 2 -b 0.0.0.0:${app_port} --access-logfile /opt/bouncer-app/app.log --error-logfile /opt/bouncer-app/app.log server:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable bouncer-app
systemctl start bouncer-app

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
${cw_agent_config}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json