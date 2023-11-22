# Infrastructure
infrastructure_kms_encryption           = false
infrastructure_logging_bucket_retention = 30

# Infrastructure VPC
infrastructure_vpc                                      = false
infrastructure_vpc_cidr_block                           = "10.0.0.0/16"
infrastructure_vpc_enable_dns_support                   = false
infrastructure_vpc_enable_dns_hostnames                 = false
infrastructure_vpc_instance_tenancy                     = "default"
infrastructure_vpc_enable_network_address_usage_metrics = false
infrastructure_vpc_assign_generated_ipv6_cidr_block     = false
infrastructure_vpc_network_enable_public                = false
infrastructure_vpc_network_enable_private               = false
infrastructure_vpc_network_availability_zones           = ["a", "b", "c"]
infrastructure_vpc_flow_logs_cloudwatch_logs            = false
infrastructure_vpc_flow_logs_retention                  = 30
infrastructure_vpc_flow_logs_s3_with_athena             = false
infrastructure_vpc_flow_logs_s3_key_prefix              = "infrastructure-vpc-flow-logs"
infrastructure_vpc_flow_logs_traffic_type               = "ALL"
