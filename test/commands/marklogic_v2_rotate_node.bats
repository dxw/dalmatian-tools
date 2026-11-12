#!/usr/bin/env bats

load ../test_helper

# Chosen per test so a tunnel left open on the machine cannot collide
ML_PORT="$(free_local_port)"

# marklogic/v2/rotate-node drains one node out of its target groups,
# terminates it, waits for the auto scaling group to replace it, names the
# replacement, puts it back behind the load balancers and checks the data
# volume followed it.
#
# Stub responses are static, so each fixture describes the state the polling
# loops are waiting for: the old node already gone from the target groups, the
# replacement already InService, the volume already re-attached. That lets
# every wait complete on its first pass, and a fixture that never reaches the
# waited-for state exercises the matching timeout. The stub also serves the
# same response to every `describe-target-health` call, whichever target group
# is asked about, so one fixture stands in for all of a group's target groups.
#
# The waits call a real `sleep` between polls, so it is shimmed to return
# immediately. `-t 1` keeps the timeout tests to a handful of attempts.
#
# MarkLogic itself is reached through the tunnel helpers, with curl stubbed
# per request (stub_marklogic_api). stub_marklogic_node stages a node whose
# forests all have in-sync replicas, which accepts a shutdown and then
# reports itself offline.

STACK="cf-ccb69c87-marklogic-cluster"
ASG_1="cf-ccb69c87-marklogic-cluster-MarkLogicServerGroup1-AAAAAAAAAAAA"
ASG_2="cf-ccb69c87-marklogic-cluster-MarkLogicServerGroup2-BBBBBBBBBBBB"
TG_8000="arn:aws:elasticloadbalancing:eu-west-2:123456789012:targetgroup/cf-ccb-AlbTa-8000/aaaaaaaaaaaaaaaa"
TG_8001="arn:aws:elasticloadbalancing:eu-west-2:123456789012:targetgroup/cf-ccb-AlbTa-8001/bbbbbbbbbbbbbbbb"
NAME_TAG_1='[{"Key":"Name","Value":"marklogic-1"}]'

# Stub keys for the calls whose arguments distinguish them from the generic
# describe. The stub sanitises every non-alphanumeric character to "_".
KEY_PREFIX="dalmatian-aws-run_command-p-example_account"
KEY_ASG_BY_NAME_2="$KEY_PREFIX-autoscaling-describe_auto_scaling_groups-auto_scaling_group_names-cf_ccb69c87_marklogic_cluster_MarkLogicServerGroup2_BBBBBBBBBBBB"
KEY_ASG_STACK="$KEY_PREFIX-autoscaling-describe_auto_scaling_groups-filters-Name_tag_marklogic_stack_name_Values_cf_ccb69c87_marklogic_cluster"
KEY_OLD_INSTANCE="$KEY_PREFIX-ec2-describe_instances-instance_ids-i_0aaaaaaaaaaaaaaaa"
KEY_NEW_INSTANCE="$KEY_PREFIX-ec2-describe_instances-instance_ids-i_0ddddddddddddddddd"
KEY_DEREGISTER_8001="$KEY_PREFIX-elbv2-deregister_targets-target_group_arn-arn_aws_elasticloadbalancing_eu_west_2_123456789012_targetgroup_cf_ccb_AlbTa_8001_bbbbbbbbbbbbbbbb"

HOST_1="ip-10-0-1-10.eu-west-2.compute.internal"
SHUTDOWN_DATA="state=shutdown&failover=true"

stub_marklogic_node() {
  local host=$1
  stub_marklogic_api GET "/manage/v2/forests?host-id=$host&format=json" marklogic-manage-forests-host-1.json
  stub_marklogic_api POST "/manage/v2/hosts/$host?format=json" marklogic-manage-host-shutdown.json 202
  stub_marklogic_api GET "/manage/v2/hosts/$host?view=status&format=json" marklogic-manage-host-status-offline.json
}

fake_instant_sleep() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/bin/sleep"
  chmod +x "$SANDBOX/bin/sleep"
}

# Stage a stub response built by transforming a fixture with jq. Any further
# arguments are passed to jq ahead of the filter, for --arg
stub_fixture_jq() {
  local key=$1 fixture=$2 filter=$3
  shift 3
  jq "$@" "$filter" "$DALMATIAN_ROOT/test/fixtures/$fixture" > "$DALMATIAN_STUB_RESPONSES/$key.out"
}

# Line number of the first argv-log entry containing $1, so tests can assert
# on the order of calls, not just that they happened
argv_line_of() {
  grep -n -m1 -F -- "$1" "$DALMATIAN_STUB_ARGV_LOG" | cut -d: -f1
}

assert_called_before() {
  local first second
  first="$(argv_line_of "$1")"
  second="$(argv_line_of "$2")"
  if [[ -z "$first" || -z "$second" || "$first" -ge "$second" ]]
  then
    fail "$(printf 'expected "%s" (line %s) to be called before "%s" (line %s)\nargv calls recorded:\n%s' \
      "$1" "${first:-none}" "$2" "${second:-none}" "$(cat "$DALMATIAN_STUB_ARGV_LOG")")"
  fi
}

setup() {
  setup_sandbox
  use_stubs
  fake_instant_sleep
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  # MarkLogic is shut down cleanly and the replacement licensed, both of
  # which need these
  export MARKLOGIC_PASSWORD="examplepassword"
  # The operator's own MarkLogic user, not the stack's admin user
  export MARKLOGIC_USER="example-user"

  # The successful rotation of node 1: three running nodes, a three-group
  # stack, node 1's group already showing its replacement in service, node 1
  # already terminated and gone from the target groups, and the data volume
  # already on the replacement
  stub_response_file "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json
  stub_response_file "$KEY_OLD_INSTANCE" marklogic-describe-instance-terminated.json
  stub_response_file "$KEY_NEW_INSTANCE" marklogic-describe-instance-replacement.json
  stub_response_file "$KEY_ASG_STACK" marklogic-describe-asg-stack.json
  stub_response_file "$KEY_PREFIX-autoscaling-describe_auto_scaling_groups" marklogic-describe-asg-replaced.json
  stub_response_file "$KEY_PREFIX-elbv2-describe_target_health" marklogic-target-health-replaced.json
  stub_response_file "$KEY_PREFIX-ec2-describe_volumes" marklogic-describe-volumes-reattached.json

  export DALMATIAN_MARKLOGIC_LOCAL_PORT="$ML_PORT"
  export DALMATIAN_MARKLOGIC_TUNNEL_ATTEMPTS=3
  stub_hold "$KEY_PREFIX-ssm-start_session"
  stub_marklogic_api GET "/manage/v2/hosts?format=json" marklogic-manage-hosts.json
  stub_marklogic_api GET "/manage/v2/forests/Documents-1?view=status&format=json" marklogic-manage-forest-status-open.json
  stub_marklogic_api GET "/manage/v2/forests/Documents-2-replica?view=status&format=json" marklogic-manage-forest-status-replica.json
  stub_marklogic_api GET "/manage/v2/forests/9001?view=status&format=json" marklogic-manage-forest-status-9001.json
  stub_marklogic_node "$HOST_1"
}

rotate() {
  run_command bin/marklogic/v2/rotate-node -i "example-infra" -e "staging" -s "marklogic-cluster" "$@"
}

# --- Arguments ---------------------------------------------------------------

@test "rotate-node prints usage with no arguments" {
  run --separate-stderr run_command bin/marklogic/v2/rotate-node
  assert_failure 1
  assert_stderr_contains "Usage: rotate-node"
  assert_output_contains "-s <stack>"
  assert_output_contains "-p <profile>"
  assert_output_contains "-n "
  assert_output_contains "-x "
  assert_output_contains "-F "
  assert_output_contains "(default: 30)"
}

@test "rotate-node requires the stack key" {
  run --separate-stderr run_command bin/marklogic/v2/rotate-node -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: rotate-node"
}

@test "rotate-node rejects a stack key outside the characters Terraform allows" {
  # The key becomes part of an EC2 filter value, where a comma would start a
  # second value and widen the match to other stacks' nodes
  run --separate-stderr rotate -s "marklogic-cluster,other" -l
  assert_failure 1
  assert_stderr_contains "Stack key 'marklogic-cluster,other' may only contain letters, digits and hyphens"
  refute_stub_called_with "describe-instances"
}

@test "rotate-node rejects a timeout that is not a whole number of minutes" {
  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t "5; echo"
  assert_failure 1
  assert_stderr_contains "-t must be a whole number of minutes"
  refute_stub_called_with "describe-instances"
}

@test "rotate-node -l lists the stack's running nodes with name, zone and AMI" {
  run rotate -l
  assert_success
  assert_stub_called_with "ec2 describe-instances --filters Name=tag:marklogic:stack:name,Values=$STACK Name=instance-state-name,Values=running"
  assert_output_contains "i-0aaaaaaaaaaaaaaaa | marklogic-1 | eu-west-2a | ami-0old0000000000000"
  assert_output_contains "i-0bbbbbbbbbbbbbbbb | No Name | eu-west-2b | ami-0old0000000000000"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node uses an explicit -p profile without resolving one" {
  # -i and -e are still needed: the stack name is derived from them
  stub_response_file "dalmatian-aws-run_command-p-example_profile-ec2-describe_instances" marklogic-describe-instances.json

  run rotate -p "example-profile" -l
  assert_success
  assert_stub_called_with "aws run-command -p example-profile ec2 describe-instances --filters Name=tag:marklogic:stack:name,Values=$STACK"
  assert_output_contains "i-0aaaaaaaaaaaaaaaa | marklogic-1"
  refute_stub_called_with "deploy list-infrastructures"
}

@test "rotate-node rejects an instance id that is not a running node of the stack" {
  run --separate-stderr rotate -I "i-00000000000000000" -y
  assert_failure 1
  assert_stderr_contains "is not a running node of stack '$STACK'"
  refute_stub_called_with "deregister-targets"
}

# --- Pre-flight refusals -----------------------------------------------------

@test "rotate-node refuses when the data volume would be deleted with the instance" {
  stub_fixture_jq "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json \
    '(.Reservations[].Instances[] | select(.InstanceId == "i-0aaaaaaaaaaaaaaaa") | .BlockDeviceMappings[] | select(.DeviceName == "/dev/sdf") | .Ebs.DeleteOnTermination) = true'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y
  assert_failure 1
  assert_stderr_contains "vol-0aaaaaaaaaaaaaaaa on i-0aaaaaaaaaaaaaaaa is set to delete on termination"
  refute_stub_called_with "deregister-targets"
  refute_stub_called_with "terminate-instance-in-auto-scaling-group"
}

@test "rotate-node refuses a node with no auto scaling group tag" {
  stub_fixture_jq "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json \
    '(.Reservations[].Instances[] | select(.InstanceId == "i-0aaaaaaaaaaaaaaaa") | .Tags) |= map(select(.Key != "aws:autoscaling:groupName"))'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y
  assert_failure 1
  assert_stderr_contains "carries no 'aws:autoscaling:groupName' tag"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node refuses a node with no data volume" {
  stub_fixture_jq "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json \
    '(.Reservations[].Instances[] | select(.InstanceId == "i-0aaaaaaaaaaaaaaaa") | .BlockDeviceMappings) |= map(select(.DeviceName != "/dev/sdf"))'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y
  assert_failure 1
  assert_stderr_contains "has no data volume at /dev/sdf"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node refuses when the group has no target groups" {
  stub_fixture_jq "$KEY_PREFIX-autoscaling-describe_auto_scaling_groups" marklogic-describe-asg-replaced.json \
    '.AutoScalingGroups[0].TargetGroupARNs = []'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y
  assert_failure 1
  assert_stderr_contains "'$ASG_1' has no target groups attached"
  refute_stub_called_with "terminate-instance-in-auto-scaling-group"
}

@test "rotate-node refuses when the group is not sized for one node" {
  stub_fixture_jq "$KEY_PREFIX-autoscaling-describe_auto_scaling_groups" marklogic-describe-asg-replaced.json \
    '.AutoScalingGroups[0].DesiredCapacity = 2 | .AutoScalingGroups[0].MaxSize = 2'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y
  assert_failure 1
  assert_stderr_contains "'$ASG_1' has a desired capacity of 2"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node refuses when the group has launch, terminate or load balancer processes suspended" {
  stub_fixture_jq "$KEY_PREFIX-autoscaling-describe_auto_scaling_groups" marklogic-describe-asg-replaced.json \
    '.AutoScalingGroups[0].SuspendedProcesses = [{"ProcessName": "Launch", "SuspensionReason": "manual"}]'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y
  assert_failure 1
  assert_stderr_contains "'$ASG_1' has suspended processes (Launch)"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node refuses to drain a node while another node is unhealthy" {
  stub_response_file "$KEY_PREFIX-elbv2-describe_target_health" marklogic-target-health-degraded.json

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y
  assert_failure 1
  assert_stderr_contains "i-0bbbbbbbbbbbbbbbb is unhealthy in target group $TG_8000 (state: unhealthy)"
  refute_stub_called_with "deregister-targets"
  refute_stub_called_with "terminate-instance-in-auto-scaling-group"
}

@test "rotate-node refuses to drain when fewer nodes are serving than the stack expects" {
  # Node 2 is not registered anywhere. Counting running instances would show
  # two peers, but the stack's groups add up to three nodes and the load
  # balancer's view is what counts
  stub_response_file "$KEY_PREFIX-elbv2-describe_target_health" marklogic-target-health-short.json

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y
  assert_failure 1
  assert_stderr_contains "Only 1 of the 2 other nodes expected are healthy in target group $TG_8000"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node checks the cluster before asking for confirmation" {
  # With no stdin the prompt would read EOF and abort, so reaching the
  # health refusal proves the checks ran first
  stub_response_file "$KEY_PREFIX-elbv2-describe_target_health" marklogic-target-health-degraded.json

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" < /dev/null
  assert_failure 1
  assert_stderr_contains "i-0bbbbbbbbbbbbbbbb is unhealthy"
  case "$stderr" in
    *Aborted*) fail "expected the health check to run before the confirmation prompt" ;;
  esac
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node aborts before draining when the confirmation is declined" {
  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" <<< "n"
  assert_failure 1
  assert_stderr_contains "Aborted"
  refute_stub_called_with "deregister-targets"
  refute_stub_called_with "terminate-instance-in-auto-scaling-group"
}

@test "rotate-node warns and proceeds when the node is the cluster's only one" {
  stub_fixture_jq "$KEY_ASG_STACK" marklogic-describe-asg-stack.json '.AutoScalingGroups |= .[0:1]'
  stub_fixture_jq "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json '.Reservations |= .[0:1]'
  stub_fixture_jq "$KEY_PREFIX-elbv2-describe_target_health" marklogic-target-health-replaced.json \
    '.TargetHealthDescriptions |= map(select(.Target.Id == "i-0ddddddddddddddddd"))'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_success
  assert_stderr_contains "only node of the cluster"
  assert_stub_called_with "terminate-instance-in-auto-scaling-group --instance-id i-0aaaaaaaaaaaaaaaa"
}

# --- The rotation ------------------------------------------------------------

@test "rotate-node drains, terminates, names the replacement and confirms the volume" {
  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_success

  assert_call_args dalmatian aws run-command -p example-account elbv2 deregister-targets --target-group-arn "$TG_8000" --targets Id=i-0aaaaaaaaaaaaaaaa
  assert_call_args dalmatian aws run-command -p example-account elbv2 deregister-targets --target-group-arn "$TG_8001" --targets Id=i-0aaaaaaaaaaaaaaaa
  assert_call_args dalmatian aws run-command -p example-account autoscaling terminate-instance-in-auto-scaling-group --instance-id i-0aaaaaaaaaaaaaaaa --no-should-decrement-desired-capacity
  assert_call_args dalmatian aws run-command -p example-account ec2 describe-instances --instance-ids i-0aaaaaaaaaaaaaaaa
  assert_call_args dalmatian aws run-command -p example-account ec2 create-tags --resources i-0ddddddddddddddddd --tags "$NAME_TAG_1"
  assert_call_args dalmatian aws run-command -p example-account ec2 describe-volumes --volume-ids vol-0aaaaaaaaaaaaaaaa

  # The safety of the whole thing is the order: look before draining, drain
  # before terminating, terminate before looking for the replacement
  assert_called_before "elbv2 describe-target-health" "elbv2 deregister-targets"
  assert_called_before "elbv2 deregister-targets" "terminate-instance-in-auto-scaling-group"
  assert_called_before "terminate-instance-in-auto-scaling-group" "ec2 create-tags"

  # The group registered the replacement itself, so the command must not
  # register anything. "elbv2 register-targets" rather than the bare verb,
  # which is a substring of the deregister calls above
  refute_stub_called_with "elbv2 register-targets"
  refute_stub_called_with "ec2 wait"

  assert_output_contains "Old node:  i-0aaaaaaaaaaaaaaaa (ami-0old0000000000000)"
  assert_output_contains "New node:  i-0ddddddddddddddddd (ami-0new0000000000000)"
  assert_output_contains "Name:      marklogic-1"
  assert_output_contains "Volume:    vol-0aaaaaaaaaaaaaaaa attached to i-0ddddddddddddddddd at /dev/sdf"
  assert_output_contains "Licence:   set from the stack's LicenseKey parameter"
}

# --- Licensing the replacement -----------------------------------------------

@test "rotate-node licenses the replacement from the stack once it is healthy" {
  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_success
  assert_call_args dalmatian marklogic set-licence -i example-infra -e staging -s marklogic-cluster -p example-account -u example-user -S -I i-0ddddddddddddddddd -y
  assert_called_before "elbv2 describe-target-health" "marklogic set-licence"
  refute_stub_called_with "examplepassword"
}

@test "rotate-node -n skips licensing and says so" {
  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1 -n
  assert_success
  refute_stub_called_with "marklogic set-licence"
  assert_output_contains "Licence:   not set (-n)"
}

@test "rotate-node asks for the MarkLogic password before starting when it is not in the environment" {
  unset MARKLOGIC_PASSWORD

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1 <<< "examplepassword"
  assert_success
  assert_stub_called_with "marklogic set-licence"
  assert_called_before "ec2 describe-instances" "elbv2 deregister-targets"
}

@test "rotate-node refuses to start without a MarkLogic password, even with -n" {
  # The clean shutdown needs MarkLogic credentials whether or not the
  # replacement is licensed
  unset MARKLOGIC_PASSWORD

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1 -n < /dev/null
  assert_failure 1
  assert_stderr_contains "No MarkLogic password given"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node asks for the MarkLogic username before starting when it is not in the environment" {
  unset MARKLOGIC_USER

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1 <<< "typed-user"
  assert_success
  assert_stub_called_with "marklogic set-licence -i example-infra -e staging -s marklogic-cluster -p example-account -u typed-user"
}

@test "rotate-node -A licenses as the stack's admin user, with a warning" {
  unset MARKLOGIC_USER
  stub_response_file "$KEY_PREFIX-cloudformation-describe_stacks" marklogic-describe-stacks.json

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1 -A
  assert_success
  assert_stderr_contains "Using the stack's admin user 'example-marklogic-admin'"
  assert_stub_called_with "marklogic set-licence -i example-infra -e staging -s marklogic-cluster -p example-account -u example-marklogic-admin"
}

@test "rotate-node reports a licensing failure and how to retry it, and exits non-zero" {
  stub_exit dalmatian-marklogic-set_licence 1

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_output_contains "Licence:   NOT set"
  assert_stderr_contains "dalmatian marklogic set-licence -i example-infra -e staging -s marklogic-cluster -u example-user -S -I i-0ddddddddddddddddd"
}

@test "rotate-node derives the name from the group's logical id when the old node had none" {
  # Rotating the unnamed node in group 2: its own group's response, the
  # terminated state of node 2, its volume, and a health response showing its
  # peers (nodes 1 and 3) healthy
  # shellcheck disable=SC2016 # $name is a jq variable, bound with --arg
  stub_fixture_jq "$KEY_ASG_BY_NAME_2" marklogic-describe-asg-replaced.json \
    '.AutoScalingGroups[0].AutoScalingGroupName = $name
     | (.AutoScalingGroups[0].Instances[] | select(.LifecycleState == "Terminating") | .InstanceId) = "i-0bbbbbbbbbbbbbbbb"' \
    --arg name "$ASG_2"
  stub_response "$KEY_PREFIX-ec2-describe_instances-instance_ids-i_0bbbbbbbbbbbbbbbb" \
    '{ "Reservations": [ { "Instances": [ { "InstanceId": "i-0bbbbbbbbbbbbbbbb", "State": { "Name": "terminated" } } ] } ] }'
  stub_response "$KEY_PREFIX-elbv2-describe_target_health" <<'JSON'
{
  "TargetHealthDescriptions": [
    { "Target": { "Id": "i-0aaaaaaaaaaaaaaaa", "Port": 8000 }, "TargetHealth": { "State": "healthy" } },
    { "Target": { "Id": "i-0ccccccccccccccccc", "Port": 8000 }, "TargetHealth": { "State": "healthy" } },
    { "Target": { "Id": "i-0ddddddddddddddddd", "Port": 8000 }, "TargetHealth": { "State": "healthy" } }
  ]
}
JSON
  stub_response "$KEY_PREFIX-ec2-describe_volumes" <<'JSON'
{
  "Volumes": [
    {
      "VolumeId": "vol-0bbbbbbbbbbbbbbbb",
      "State": "in-use",
      "Attachments": [ { "InstanceId": "i-0ddddddddddddddddd", "Device": "/dev/sdf", "State": "attached" } ]
    }
  ]
}
JSON

  stub_marklogic_node "ip-10-0-2-10.eu-west-2.compute.internal"

  run --separate-stderr rotate -I "i-0bbbbbbbbbbbbbbbb" -y -t 1
  assert_success
  assert_stub_called_with "describe-auto-scaling-groups --auto-scaling-group-names $ASG_2"
  assert_call_args dalmatian aws run-command -p example-account ec2 create-tags --resources i-0ddddddddddddddddd --tags '[{"Key":"Name","Value":"marklogic-2"}]'
}

@test "rotate-node falls back to the availability zone for a name when there is no logical id either" {
  stub_fixture_jq "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json \
    '(.Reservations[].Instances[] | select(.InstanceId == "i-0aaaaaaaaaaaaaaaa") | .Tags) |= map(select(.Key != "Name" and .Key != "aws:cloudformation:logical-id"))'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_success
  assert_call_args dalmatian aws run-command -p example-account ec2 create-tags --resources i-0ddddddddddddddddd --tags '[{"Key":"Name","Value":"marklogic-eu-west-2a"}]'
}

@test "rotate-node passes a name containing shorthand delimiters safely" {
  stub_fixture_jq "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json \
    '(.Reservations[].Instances[] | select(.InstanceId == "i-0aaaaaaaaaaaaaaaa") | .Tags[] | select(.Key == "Name") | .Value) = "ml=1,Value=x"'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_success
  assert_call_args dalmatian aws run-command -p example-account ec2 create-tags --resources i-0ddddddddddddddddd --tags '[{"Key":"Name","Value":"ml=1,Value=x"}]'
}

# --- Failures while the old node is still alive -----------------------------

@test "rotate-node re-registers the node and does not terminate it when draining times out" {
  stub_response_file "$KEY_PREFIX-elbv2-describe_target_health" marklogic-target-health-draining.json

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "i-0aaaaaaaaaaaaaaaa was still draining after 1 minute(s)"
  assert_stderr_contains "re-registered with its target groups"
  assert_call_args dalmatian aws run-command -p example-account elbv2 register-targets --target-group-arn "$TG_8000" --targets Id=i-0aaaaaaaaaaaaaaaa
  assert_call_args dalmatian aws run-command -p example-account elbv2 register-targets --target-group-arn "$TG_8001" --targets Id=i-0aaaaaaaaaaaaaaaa
  refute_stub_called_with "terminate-instance-in-auto-scaling-group"
  # MarkLogic is only shut down once the node has drained
  refute_stub_called_with "--request POST --url http://localhost:${ML_PORT}/manage/v2/hosts/"
}

@test "rotate-node re-registers the node when an AWS call fails before it is terminated" {
  stub_exit "$KEY_DEREGISTER_8001" 1

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure
  assert_stderr_contains "stopped before i-0aaaaaaaaaaaaaaaa was terminated"
  assert_call_args dalmatian aws run-command -p example-account elbv2 register-targets --target-group-arn "$TG_8000" --targets Id=i-0aaaaaaaaaaaaaaaa
  assert_call_args dalmatian aws run-command -p example-account elbv2 register-targets --target-group-arn "$TG_8001" --targets Id=i-0aaaaaaaaaaaaaaaa
  refute_stub_called_with "terminate-instance-in-auto-scaling-group"
}

# --- Clean shutdown in MarkLogic ---------------------------------------------

@test "rotate-node shuts MarkLogic down through another node with fast failover before terminating" {
  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_success

  # The Manage API is reached through another node, not the one going away
  assert_stub_called_with "ssm start-session --document-name AWS-StartPortForwardingSession --target i-0bbbbbbbbbbbbbbbb --parameters portNumber=8002,localPortNumber=${ML_PORT}"
  refute_stub_called_with "--target i-0aaaaaaaaaaaaaaaa --parameters portNumber=8002"
  assert_stub_called_with "--request POST --url http://localhost:${ML_PORT}/manage/v2/hosts/$HOST_1?format=json"
  assert_stub_called_with "--header Content-type: application/x-www-form-urlencoded --data $SHUTDOWN_DATA"
  refute_stub_called_with "examplepassword"

  assert_called_before "elbv2 deregister-targets" "--request POST --url http://localhost:${ML_PORT}/manage/v2/hosts/$HOST_1"
  # The order is read from the argv log, which records "?" escaped as "\?"
  assert_called_before "--url http://localhost:${ML_PORT}/manage/v2/hosts/$HOST_1\\?view=status" "terminate-instance-in-auto-scaling-group"
  assert_output_contains "MarkLogic: shut down with failover"
}

@test "rotate-node refuses before draining when a forest it serves has no in-sync replica" {
  jq '.["forest-status"]["status-properties"].state.value = "async replicating"' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-forest-status-9001.json" > "$SANDBOX/9001.json"
  { cat "$SANDBOX/9001.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_forests_9001_view_status_format_json.out"

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "Documents-1 (replicas: 9001 async replicating)"
  assert_stderr_contains "-F"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node refuses a forest it serves with no replica at all" {
  jq 'del(.["forest-status"]["status-properties"]["replica-forests"])' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-forest-status-open.json" > "$SANDBOX/open.json"
  { cat "$SANDBOX/open.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_forests_Documents_1_view_status_format_json.out"

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "Documents-1 (replicas: none)"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node refuses a forest whose state it cannot read" {
  printf '{"forest-status": {"name": "Documents-2-replica"}}\n200\n' \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_forests_Documents_2_replica_view_status_format_json.out"

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "Documents-2-replica (state unknown)"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node -F proceeds even when a forest has no in-sync replica" {
  jq 'del(.["forest-status"]["status-properties"]["replica-forests"])' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-forest-status-open.json" > "$SANDBOX/open.json"
  { cat "$SANDBOX/open.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_forests_Documents_1_view_status_format_json.out"

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1 -F
  assert_success
  assert_stderr_contains "Documents-1 (replicas: none)"
  assert_stub_called_with "terminate-instance-in-auto-scaling-group"
}

@test "rotate-node refuses when it finds no forests on the node, unless -F" {
  printf '{"forest-default-list": {"list-items": {"list-count": {"value": 0}}}}\n200\n' \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_forests_host_id_ip_10_0_1_10_eu_west_2_compute_internal_format_json.out"

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "Found no forests on MarkLogic host $HOST_1"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node refuses before draining when no other node is reachable to manage the shutdown" {
  stub_exit "$KEY_PREFIX-ssm-start_session-document_name-AWS_StartPortForwardingSession-target-i_0bbbbbbbbbbbbbbbb" 1
  stub_exit "$KEY_PREFIX-ssm-start_session-document_name-AWS_StartPortForwardingSession-target-i_0ccccccccccccccccc" 1

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "No other node of stack '$STACK' is reachable through Systems Manager"
  refute_stub_called_with "deregister-targets"
}

@test "rotate-node re-registers the node and does not terminate it when MarkLogic refuses the shutdown" {
  stub_marklogic_api POST "/manage/v2/hosts/$HOST_1?format=json" - 403

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "MarkLogic refused to shut down $HOST_1 (HTTP 403)"
  assert_call_args dalmatian aws run-command -p example-account elbv2 register-targets --target-group-arn "$TG_8000" --targets Id=i-0aaaaaaaaaaaaaaaa
  refute_stub_called_with "terminate-instance-in-auto-scaling-group"
}

@test "rotate-node stops without terminating or re-registering when the host never reports offline" {
  stub_marklogic_api GET "/manage/v2/hosts/$HOST_1?view=status&format=json" marklogic-manage-host-status-1.json

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "MarkLogic on $HOST_1 was told to shut down but did not report offline within 1 minute(s)"
  refute_stub_called_with "terminate-instance-in-auto-scaling-group"
  refute_stub_called_with "elbv2 register-targets --target-group-arn $TG_8000 --targets Id=i-0aaaaaaaaaaaaaaaa"
}

@test "rotate-node -x terminates without the clean shutdown" {
  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1 -x
  assert_success
  refute_stub_called_with "--request POST --url http://localhost:${ML_PORT}/manage/v2/hosts/"
  assert_stub_called_with "terminate-instance-in-auto-scaling-group"
  assert_output_contains "MarkLogic: not shut down first (-x)"
}

@test "rotate-node waits for the replacement's forests to catch up, and reports when they do not" {
  # A forest still copying changes from its master is not yet a usable
  # replica; rotating the next node before it catches up risks failing over
  # to stale data
  jq '.["forest-status"]["status-properties"].state.value = "async replicating"' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-forest-status-replica.json" > "$SANDBOX/replica.json"
  { cat "$SANDBOX/replica.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_forests_Documents_2_replica_view_status_format_json.out"

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stub_called_with "terminate-instance-in-auto-scaling-group"
  assert_stderr_contains "forests on $HOST_1 had not caught up within 1 minute(s): Documents-2-replica (async replicating)"
  assert_stderr_contains "before rotating another node"
  assert_output_contains "Forests:   NOT caught up"
}

# --- Failures after termination ---------------------------------------------

@test "rotate-node reports when the old node does not finish terminating" {
  stub_response "$KEY_OLD_INSTANCE" \
    '{ "Reservations": [ { "Instances": [ { "InstanceId": "i-0aaaaaaaaaaaaaaaa", "State": { "Name": "shutting-down" } } ] } ] }'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "i-0aaaaaaaaaaaaaaaa had not terminated after 1 minute(s) (last state: shutting-down)"
  refute_stub_called_with "elbv2 register-targets"
}

@test "rotate-node reports when the data volume stays attached to the terminated node" {
  stub_response_file "$KEY_PREFIX-ec2-describe_volumes" marklogic-describe-volumes-still-attached.json

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "vol-0aaaaaaaaaaaaaaaa is still attached to the terminated instance i-0aaaaaaaaaaaaaaaa after 1 minute(s)"
}

@test "rotate-node reports when the group launches no replacement" {
  stub_fixture_jq "$KEY_PREFIX-autoscaling-describe_auto_scaling_groups" marklogic-describe-asg-replaced.json \
    '.AutoScalingGroups[0].Instances |= map(select(.InstanceId == "i-0aaaaaaaaaaaaaaaa"))'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_stderr_contains "'$ASG_1' launched no replacement within 1 minute(s)"
  refute_stub_called_with "ec2 create-tags"
}

@test "rotate-node names a replacement stuck at the lifecycle hook and reports it" {
  stub_fixture_jq "$KEY_PREFIX-autoscaling-describe_auto_scaling_groups" marklogic-describe-asg-replaced.json \
    '(.AutoScalingGroups[0].Instances[] | select(.InstanceId == "i-0ddddddddddddddddd") | .LifecycleState) = "Pending:Wait"'

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_call_args dalmatian aws run-command -p example-account ec2 create-tags --resources i-0ddddddddddddddddd --tags "$NAME_TAG_1"
  assert_stderr_contains "i-0ddddddddddddddddd did not reach InService within 1 minute(s) (last state: Pending:Wait)"
  assert_stderr_contains "NodeManager"
}

@test "rotate-node registers the replacement itself when the group has not, and reports if it never becomes healthy" {
  stub_response_file "$KEY_PREFIX-elbv2-describe_target_health" marklogic-target-health-missing-replacement.json

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  assert_call_args dalmatian aws run-command -p example-account elbv2 register-targets --target-group-arn "$TG_8000" --targets Id=i-0ddddddddddddddddd
  assert_call_args dalmatian aws run-command -p example-account elbv2 register-targets --target-group-arn "$TG_8001" --targets Id=i-0ddddddddddddddddd
  assert_stderr_contains "i-0ddddddddddddddddd did not become healthy in every target group within 1 minute(s)"
}

@test "rotate-node fails and reports when the data volume did not re-attach" {
  stub_response_file "$KEY_PREFIX-ec2-describe_volumes" marklogic-describe-volumes-available.json

  run --separate-stderr rotate -I "i-0aaaaaaaaaaaaaaaa" -y -t 1
  assert_failure 1
  # Everything up to the volume check still ran: the replacement is up, named
  # and serving, and the operator is told what to look at
  assert_call_args dalmatian aws run-command -p example-account ec2 create-tags --resources i-0ddddddddddddddddd --tags "$NAME_TAG_1"
  assert_stderr_contains "vol-0aaaaaaaaaaaaaaaa is not attached to i-0ddddddddddddddddd at /dev/sdf"
  assert_stderr_contains "state: available"
  assert_stderr_contains "NodeManager"
}
