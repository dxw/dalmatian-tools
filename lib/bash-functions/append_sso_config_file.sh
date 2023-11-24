#!/bin/bash
set -e
set -o pipefail

# Dalmatian specific function
# Appends AWS sso config to the provided
# configuration file
function append_sso_config_file {
  config_file="$1"
  profile_name="$2"
  sso_start_url="$3"
  sso_region="$4"
  sso_account_id="$5"
  sso_role_name="$6"
  region="$7"

  cat <<EOT >> "$config_file"
[profile $profile_name]
sso_start_url = $sso_start_url
sso_region = $sso_region
sso_account_id = $sso_account_id
sso_role_name = $sso_role_name
region = $region

EOT
}
