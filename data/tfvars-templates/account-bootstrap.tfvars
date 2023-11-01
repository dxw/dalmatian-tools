# Logging
logging_bucket_retention = 30

# Cloudtrail
enable_cloudtrail                          = true
cloudtrail_log_retention                   = 30
cloudtrail_log_prefix                      = "cloudtrail"
cloudtrail_kms_encryption                  = false
cloudtrail_s3_access_logs                  = false
cloudtrail_athena_glue_tables              = false
cloudtrail_athena_s3_output_retention      = 30
cloudtrail_athena_s3_output_kms_encryption = false

# Cloudwatch Slack Alerts
enable_cloudwatch_slack_alerts         = false
cloudwatch_slack_alerts_hook_url       = ""
cloudwatch_slack_alerts_channel        = ""
cloudwatch_slack_alerts_kms_encryption = false
cloudwatch_slack_alerts_log_retention  = 30

# Cloudwatch OpsGenie Alerts
enable_cloudwatch_opsgenie_alerts             = false
cloudwatch_opsgenie_alerts_sns_endpoint       = ""
cloudwatch_opsgenie_alerts_sns_kms_encryption = false

# CodeStar connections
# eg. codestar_connections ={ github = { provider_type = "GitHub" } }
codestar_connections = {}
