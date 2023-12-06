# Infrastructure
infrastructure_kms_encryption           = false
infrastructure_logging_bucket_retention = 30

# Route53
route53_root_hosted_zone_domain_name      = ""
aws_profile_name_route53_root             = "dalmatian-main"
enable_infrastructure_route53_hosted_zone = false

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
