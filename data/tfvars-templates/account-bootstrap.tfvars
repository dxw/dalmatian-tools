# Logging
logging_bucket_retention = 30

# Delete Default Resources Lambda
enable_delete_default_resources                = false
delete_default_resources_lambda_kms_encryption = false
delete_default_resources_log_retention         = 30

# Route53
route53_root_hosted_zone_domain_name = ""

# Cloudtrail
enable_cloudtrail                          = false
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
