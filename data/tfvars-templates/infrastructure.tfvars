# Infrastructure
infrastructure_kms_encryption            = false
infrastructure_logging_bucket_retention  = 30
infrastructure_kms_key_policy_statements = ""

# Route53
route53_root_hosted_zone_domain_name      = ""
aws_profile_name_route53_root             = "dalmatian-main"
enable_infrastructure_route53_hosted_zone = false

# Dockerhub
infrastructure_dockerhub_email    = ""
infrastructure_dockerhub_username = ""
infrastructure_dockerhub_token    = ""

# Infrastructure VPC
infrastructure_vpc                                          = false
infrastructure_vpc_cidr_block                               = "10.0.0.0/16"
infrastructure_vpc_enable_dns_support                       = false
infrastructure_vpc_enable_dns_hostnames                     = false
infrastructure_vpc_instance_tenancy                         = "default"
infrastructure_vpc_enable_network_address_usage_metrics     = false
infrastructure_vpc_assign_generated_ipv6_cidr_block         = false
infrastructure_vpc_network_enable_public                    = false
infrastructure_vpc_network_enable_private                   = false
infrastructure_vpc_network_availability_zones               = ["a", "b", "c"]
infrastructure_vpc_flow_logs_cloudwatch_logs                = false
infrastructure_vpc_flow_logs_retention                      = 30
infrastructure_vpc_flow_logs_s3_with_athena                 = false
infrastructure_vpc_flow_logs_s3_key_prefix                  = "infrastructure-vpc-flow-logs"
infrastructure_vpc_flow_logs_traffic_type                   = "ALL"
infrastructure_vpc_network_acl_egress_lockdown_public       = false
infrastructure_vpc_network_acl_egress_lockdown_private      = false
infrastructure_vpc_network_acl_ingress_lockdown_public      = false
infrastructure_vpc_network_acl_ingress_lockdown_private     = false
infrastructure_vpc_network_acl_egress_custom_rules_public   = []
infrastructure_vpc_network_acl_egress_custom_rules_private  = []
infrastructure_vpc_network_acl_ingress_custom_rules_public  = []
infrastructure_vpc_network_acl_ingress_custom_rules_private = []
enable_infrastructure_vpc_transfer_s3_bucket                = false
infrastructure_vpc_transfer_s3_bucket_access_vpc_ids        = []

# Infrastructure ECS Cluster
enable_infrastructure_ecs_cluster                                      = false
infrastructure_ecs_cluster_ami_version                                 = "*"
infrastructure_ecs_cluster_ebs_docker_storage_volume_size              = 22
infrastructure_ecs_cluster_ebs_docker_storage_volume_type              = "gp3"
infrastructure_ecs_cluster_publicly_avaialble                          = false
infrastructure_ecs_cluster_custom_security_group_rules                 = {}
infrastructure_ecs_cluster_instance_type                               = "t3.small"
infrastructure_ecs_cluster_termination_timeout                         = 900
infrastructure_ecs_cluster_draining_lambda_enabled                     = false
infrastructure_ecs_cluster_draining_lambda_log_retention               = 30
infrastructure_ecs_cluster_min_size                                    = 2
infrastructure_ecs_cluster_max_size                                    = 2
infrastructure_ecs_cluster_max_instance_lifetime                       = 86400
infrastructure_ecs_cluster_instance_refresh_lambda_schedule_expression = ""
infrastructure_ecs_cluster_instance_refresh_lambda_log_retention       = 30
infrastructure_ecs_cluster_autoscaling_time_based_max                  = []
infrastructure_ecs_cluster_autoscaling_time_based_min                  = []
infrastructure_ecs_cluster_autoscaling_time_based_custom               = []
infrastructure_ecs_cluster_enable_debug_mode                           = false
infrastructure_ecs_cluster_enable_execute_command_logging              = false
infrastructure_ecs_cluster_syslog_endpoint                             = ""
infrastructure_ecs_cluster_syslog_permitted_peer                       = ""
infrastructure_ecs_cluster_logspout_command                            = []

# Infrastructure ECS Cluster Alerts
## Autoscaling Group CPU
enable_infrastructure_ecs_cluster_asg_cpu_alert             = false
infrastructure_ecs_cluster_asg_cpu_alert_evaluation_periods = 5
infrastructure_ecs_cluster_asg_cpu_alert_period             = 60
infrastructure_ecs_cluster_asg_cpu_alert_threshold          = 90
infrastructure_ecs_cluster_asg_cpu_alert_slack              = false
infrastructure_ecs_cluster_asg_cpu_alert_opsgenie           = false
## Pending Tasks
enable_infrastructure_ecs_cluster_pending_task_alert                = false
infrastructure_ecs_cluster_pending_task_metric_lambda_log_retention = 30
infrastructure_ecs_cluster_pending_task_alert_evaluation_periods    = 5
infrastructure_ecs_cluster_pending_task_alert_period                = 60
infrastructure_ecs_cluster_pending_task_alert_threshold             = 50
infrastructure_ecs_cluster_pending_task_alert_slack                 = false
infrastructure_ecs_cluster_pending_task_alert_opsgenie              = false
## Container Instance ASG Instance diff
enable_infrastructure_ecs_cluster_ecs_asg_diff_alert                = false
infrastructure_ecs_cluster_ecs_asg_diff_metric_lambda_log_retention = 30
infrastructure_ecs_cluster_ecs_asg_diff_alert_evaluation_periods    = 15
infrastructure_ecs_cluster_ecs_asg_diff_alert_period                = 60
infrastructure_ecs_cluster_ecs_asg_diff_alert_threshold             = 1
infrastructure_ecs_cluster_ecs_asg_diff_alert_slack                 = false
infrastructure_ecs_cluster_ecs_asg_diff_alert_opsgenie              = false

# Infrastructure ECS Cluster Services
infrastructure_ecs_cluster_service_defaults                       = {}
infrastructure_ecs_cluster_services                               = {}
infrastructure_ecs_cluster_services_alb_ip_allow_list             = ["0.0.0.0/0"]
enable_infrastructure_ecs_cluster_services_alb_logs               = false
infrastructure_ecs_cluster_services_alb_enable_global_accelerator = false
infrastructure_ecs_cluster_services_alb_logs_retention            = 30

# Infrastructure ECS Cluster EFS
enable_infrastructure_ecs_cluster_efs        = false
ecs_cluster_efs_performance_mode             = "generalPurpose"
ecs_cluster_efs_throughput_mode              = "elastic"
ecs_cluster_efs_infrequent_access_transition = 0
ecs_cluster_efs_directories                  = []

# Infrastructure ECS Cluster WAF
infrastructure_ecs_cluster_wafs = {}

# Infrastructure RDS
infrastructure_rds_defaults                     = {}
infrastructure_rds                              = {}
enable_infrastructure_rds_backup_to_s3          = false
infrastructure_rds_backup_to_s3_cron_expression = "cron(0 20 ? * * *)"
infrastructure_rds_backup_to_s3_retention       = 30

# Infrastructure ElastiCache
infrastructure_elasticache_defaults = {}
infrastructure_elasticache          = {}

# Infrastructure Bastion Host
enable_infrastructure_bastion_host                      = false
infrastructure_bastion_host_custom_security_group_rules = {}

# Custom CloudFormation Stacks
enable_cloudformatian_s3_template_store = false
custom_cloudformation_stacks            = {}

# Custom S3 buckets
custom_s3_buckets = {}

# Custom Hosted Zones
custom_route53_hosted_zones = {}

# Datadog
infrastructure_datadog_api_key                  = ""
infrastructure_datadog_app_key                  = ""
infrastructure_datadog_region                   = ""
enable_infrastructure_ecs_cluster_datadog_agent = false

# Custom Lambda Functions
custom_lambda_functions = {}

# Custom tags
custom_resource_tags       = []
custom_resource_tags_delay = 0
