{
  "widgets": [
    {
      "type": "text",
      "x": 0, "y": 0, "width": 24, "height": 1,
      "properties": {
        "markdown": "# Bouncer — App & Infra Dashboard\n**Environment:** dev | **Region:** ${region}"
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 1, "width": 12, "height": 6,
      "properties": {
        "title": "Request Count",
        "view": "timeSeries",
        "region": "${region}",
        "stat": "Sum",
        "period": 60,
        "metrics": [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "${alb_arn_suffix}", {"label": "Requests"}]
        ],
        "yAxis": {"left": {"min": 0}}
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 1, "width": 12, "height": 6,
      "properties": {
        "title": "Target Response Time (Latency)",
        "view": "timeSeries",
        "region": "${region}",
        "period": 60,
        "metrics": [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "${alb_arn_suffix}", {"stat": "Average", "label": "Avg"}],
          ["...", {"stat": "p99", "label": "p99"}]
        ],
        "yAxis": {"left": {"min": 0, "label": "seconds"}}
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 7, "width": 12, "height": 6,
      "properties": {
        "title": "Error Rate (%)",
        "view": "timeSeries",
        "region": "${region}",
        "period": 60,
        "metrics": [
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", "${alb_arn_suffix}", {"stat": "Sum", "id": "m1", "visible": false}],
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", "${alb_arn_suffix}", {"stat": "Sum", "id": "m2", "visible": false}],
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "${alb_arn_suffix}", {"stat": "Sum", "id": "m3", "visible": false}],
          [{"expression": "IF(m3 > 0, ((m1 + m2) / m3) * 100, 0)", "label": "5xx Error Rate %", "id": "e1"}]
        ],
        "yAxis": {"left": {"min": 0, "label": "%"}}
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 7, "width": 12, "height": 6,
      "properties": {
        "title": "Target Group Host Health",
        "view": "timeSeries",
        "region": "${region}",
        "period": 60,
        "stat": "Average",
        "metrics": [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", "${target_group_arn_suffix}", "LoadBalancer", "${alb_arn_suffix}", {"label": "Healthy"}],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", "${target_group_arn_suffix}", "LoadBalancer", "${alb_arn_suffix}", {"label": "Unhealthy"}]
        ],
        "yAxis": {"left": {"min": 0}}
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 13, "width": 12, "height": 6,
      "properties": {
        "title": "ASG Capacity (Healthy Hosts)",
        "view": "timeSeries",
        "region": "${region}",
        "period": 60,
        "stat": "Average",
        "metrics": [
          ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", "${asg_name}", {"label": "In Service"}],
          ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", "${asg_name}", {"label": "Desired"}]
        ],
        "yAxis": {"left": {"min": 0}}
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 13, "width": 12, "height": 6,
      "properties": {
        "title": "RDS CPU Utilization",
        "view": "timeSeries",
        "region": "${region}",
        "period": 60,
        "stat": "Average",
        "metrics": [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${db_instance_id}", {"label": "CPU %"}]
        ],
        "yAxis": {"left": {"min": 0, "max": 100, "label": "%"}}
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 19, "width": 12, "height": 6,
      "properties": {
        "title": "RDS Database Connections",
        "view": "timeSeries",
        "region": "${region}",
        "period": 60,
        "stat": "Average",
        "metrics": [
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "${db_instance_id}", {"label": "Connections"}]
        ],
        "yAxis": {"left": {"min": 0}}
      }
    }
  ]
}