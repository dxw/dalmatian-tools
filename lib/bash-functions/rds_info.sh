#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to describe an infrastructure RDS, whether it
# was deployed as an Aurora cluster or a DB instance, as one JSON object:
#
#   {
#     "type": "cluster" | "instance",
#     "engine": "<RDS engine>",
#     "endpoint": "<writer address>",
#     "backup_host": "<DB_HOST the utilities task backs up from>",
#     "master_username": "<root user>",
#     "master_user_secret_arn": "<Secrets Manager ARN of the root password>"
#   }
#
# backup_host is the cluster reader endpoint, because that is what the
# utilities task definition gives the S3 backup script as DB_HOST, and the
# backup keys are prefixed with it.
#
# @param -p <aws_sso_profile>  AWS SSO profile
# @param -i <rds_identifier>   RDS identifier (<resource prefix hash>-<rds name>)
function rds_info {
  local OPTIND opt OPTARG PROFILE RDS_IDENTIFIER DB_CLUSTERS DB_INSTANCES ERROR_FILE STATUS
  OPTIND=1
  while getopts "p:i:" opt; do
    case $opt in
      p)
        PROFILE="$OPTARG"
        ;;
      i)
        RDS_IDENTIFIER="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_info\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$PROFILE" || -z "$RDS_IDENTIFIER" ]]
  then
    echo "Invalid \`rds_info\` function usage" >&2
    exit 1
  fi

  # Only RDS's own "not found" faults mean "try the other type" or "no such
  # RDS". Anything else -- an expired session, AccessDenied, throttling -- is
  # passed through with its message and status rather than misreported as a
  # missing RDS
  ERROR_FILE="$(mktemp)"
  STATUS=0
  DB_CLUSTERS="$("$APP_ROOT/bin/dalmatian" aws run-command \
    -p "$PROFILE" \
    rds describe-db-clusters \
    --db-cluster-identifier "$RDS_IDENTIFIER" \
    2>"$ERROR_FILE")" || STATUS=$?

  if [ "$STATUS" -eq 0 ]
  then
    rm -f "$ERROR_FILE"
    echo "$DB_CLUSTERS" | jq -c '.DBClusters[0] | {
      type: "cluster",
      engine: .Engine,
      endpoint: .Endpoint,
      backup_host: .ReaderEndpoint,
      master_username: .MasterUsername,
      master_user_secret_arn: .MasterUserSecret.SecretArn
    }'
    return
  fi
  if ! grep -q "DBClusterNotFoundFault" "$ERROR_FILE"
  then
    cat "$ERROR_FILE" >&2
    rm -f "$ERROR_FILE"
    exit "$STATUS"
  fi

  STATUS=0
  DB_INSTANCES="$("$APP_ROOT/bin/dalmatian" aws run-command \
    -p "$PROFILE" \
    rds describe-db-instances \
    --db-instance-identifier "$RDS_IDENTIFIER" \
    2>"$ERROR_FILE")" || STATUS=$?

  if [ "$STATUS" -eq 0 ]
  then
    rm -f "$ERROR_FILE"
    echo "$DB_INSTANCES" | jq -c '.DBInstances[0] | {
      type: "instance",
      engine: .Engine,
      endpoint: .Endpoint.Address,
      backup_host: .Endpoint.Address,
      master_username: .MasterUsername,
      master_user_secret_arn: .MasterUserSecret.SecretArn
    }'
    return
  fi
  if ! grep -q "DBInstanceNotFound" "$ERROR_FILE"
  then
    cat "$ERROR_FILE" >&2
    rm -f "$ERROR_FILE"
    exit "$STATUS"
  fi
  rm -f "$ERROR_FILE"

  err "RDS $RDS_IDENTIFIER does not exist"
  exit 1
}
