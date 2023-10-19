# Cloudtrail
enable_cloudtrail        = true
cloudtrail_log_retention = 30
cloudtrail_log_prefix    = "cloudtrail"

# Cloudwatch Slack Alerts
enable_cloudwatch_slack_alerts   = false
cloudwatch_slack_alerts_hook_url = ""
cloudwatch_slack_alerts_channel  = ""

# Cloudwatch OpsGenie Alerts
enable_cloudwatch_opsgenie_alerts             = false
cloudwatch_opsgenie_alerts_sns_endpoint       = ""
cloudwatch_opsgenie_alerts_sns_kms_encryption = false
