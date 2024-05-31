#!/bin/bash
set -e
set -o pipefail

# Dalmatian specific function
# Appends an import block to the provided
# terraform configuration file
function append_import_block {
  config_file="$1"

  read -rp "to: " TO
  PROVIDER=$(echo "$TO" | cut -d '_' -f1)
  RESOURCE=$(echo "$TO" | cut -d '_' -f2- | cut -d '.' -f1)
  IMPORT_DOC_URL="https://registry.terraform.io/providers/hashicorp/${PROVIDER}/latest/docs/resources/${RESOURCE}#import"
  echo "Terraform import docs for ${PROVIDER}_${RESOURCE}: $IMPORT_DOC_URL"
  read -rp "id: " ID

  cat <<EOT >> "$config_file"
import {
  to = $TO
  id = "$ID"
}

EOT
}
