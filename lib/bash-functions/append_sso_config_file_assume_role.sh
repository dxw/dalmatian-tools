#!/bin/bash
set -e
set -o pipefail

# Dalmatian specific function
# Appends a profile which assumes a role to the
# configuration file
function append_sso_config_file_assume_role {
  config_file="$1"
  profile_name="$2"
  source_profile="$3"
  role_arn="$4"
  region="$5"

  cat <<EOT >> "$config_file"
[profile $profile_name]
source_profile = $source_profile
role_arn = $role_arn
region = $region

EOT
}
