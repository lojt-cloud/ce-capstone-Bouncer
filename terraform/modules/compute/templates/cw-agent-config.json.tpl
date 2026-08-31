{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/bouncer-app/app.log",
            "log_group_name": "${app_log_group_name}",
            "log_stream_name": "{instance_id}/app",
            "timestamp_format": "%Y-%m-%dT%H:%M:%S.%fZ"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "${app_log_group_name}",
            "log_stream_name": "{instance_id}/boot"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu":  { "measurement": ["cpu_usage_active"], "metrics_collection_interval": 60, "totalcpu": true },
      "mem":  { "measurement": ["mem_used_percent"], "metrics_collection_interval": 60 },
      "disk": { "measurement": ["disk_used_percent"], "metrics_collection_interval": 60, "resources": ["/"] }
    }
  }
}