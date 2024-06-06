# Infrastructure
infrastructure_kms_encryption           = false
infrastructure_logging_bucket_retention = 30

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
enable_infrastructure_ecs_cluster                         = false
infrastructure_ecs_cluster_ami_version                    = "*"
infrastructure_ecs_cluster_ebs_docker_storage_volume_size = 22
infrastructure_ecs_cluster_ebs_docker_storage_volume_type = "gp3"
infrastructure_ecs_cluster_publicly_avaialble             = false
infrastructure_ecs_cluster_custom_security_group_rules    = {}
infrastructure_ecs_cluster_instance_type                  = "t3.small"
infrastructure_ecs_cluster_termination_timeout            = 900
infrastructure_ecs_cluster_draining_lambda_enabled        = false
infrastructure_ecs_cluster_draining_lambda_log_retention  = 30
infrastructure_ecs_cluster_min_size                       = 2
infrastructure_ecs_cluster_max_size                       = 2
infrastructure_ecs_cluster_max_instance_lifetime          = 86400
infrastructure_ecs_cluster_autoscaling_time_based_max     = []
infrastructure_ecs_cluster_autoscaling_time_based_min     = []
infrastructure_ecs_cluster_autoscaling_time_based_custom  = []

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
infrastructure_rds_defaults = {}
infrastructure_rds          = {}

# Infrastructure ElastiCache
infrastructure_elasticache_defaults = {}
infrastructure_elasticache          = {}

# Custom CloudFormation Stacks
enable_cloudformatian_s3_template_store = false
custom_cloudformation_stacks            = {}

# Custom S3 buckets
custom_s3_buckets = {}

# Custom Hosted Zones
custom_route53_hosted_zones = {}
