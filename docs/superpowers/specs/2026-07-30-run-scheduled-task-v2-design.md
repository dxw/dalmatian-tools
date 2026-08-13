# Design: `dalmatian service run-scheduled-task` (v2)

Date: 2026-07-30

## Problem

Dalmatian defines several ECS scheduled tasks entirely in the Terraform
infrastructure repo as CloudWatch Event Rules that target `ecs run-task`.
There is no CLI command to trigger these on-demand, outside their cron
schedule. Operators sometimes need to run a scheduled task now (e.g. a manual
S3->Azure sync or an ad-hoc RDS backup) without waiting for the schedule.

## Scheduled task systems in scope

All three share the same shape: a `aws_cloudwatch_event_rule` (cron) plus an
`aws_cloudwatch_event_target` that points at an ECS cluster and carries an
`ecs_target` (task definition, launch type, network config) and an `input`
(container overrides).

| System | Cluster | Launch type | Network config | Overrides |
|---|---|---|---|---|
| `s3-to-azure` | infrastructure-utilities | FARGATE | in `ecs_target` | env `SOURCE`/`DESTINATION` |
| `rds-s3-backups` | infrastructure-utilities | FARGATE | in `ecs_target` | `command` |
| service `scheduled_tasks` | infrastructure | EC2 | none (bridge) | none |

Rule naming is always `${resource_prefix}-<...>` where
`resource_prefix = ${project_name}-${infrastructure}-${environment}`.

## Approach

A single **generic** runner that reads whatever the deployed event target
defines and replays it via `ecs run-task`. Because the SOURCE/DESTINATION and
command overrides live only in the event target (not the task definition),
reading the target guarantees the on-demand run matches the scheduled run and
cannot drift.

### Command

`bin/service/v2/run-scheduled-task`

### Flags

- `-i <infrastructure>` (required)
- `-e <environment>` (required)
- `-t <task_name>` (optional; fzf picker if omitted)
- `-h` help

### Flow

1. Validate `-i`/`-e`. Resolve profile with `resolve_aws_profile`. Read
   `project_name` from setup config. Build `resource_prefix`.
2. `events list-rules --name-prefix "${resource_prefix}-"` and filter to rules
   that have an ECS target. These are the selectable scheduled tasks.
3. Task selection: `-t` must exactly match a listed rule; otherwise present an
   fzf picker (guarded by `DALMATIAN_FZF_ENABLED`, falling back to `select`).
4. `events list-targets-by-rule` for the chosen rule. Extract from the ECS
   target:
   - `Arn` -> cluster (`--cluster`)
   - `EcsParameters.TaskDefinitionArn` -> `--task-definition`
   - `EcsParameters.LaunchType` -> `--launch-type`
   - `EcsParameters.PlatformVersion` (if present) -> `--platform-version`
   - `EcsParameters.PropagateTags` (if present) -> `--propagate-tags`
   - `EcsParameters.NetworkConfiguration` (if present) ->
     `--network-configuration`
   - `Input` -> `--overrides` (only if non-empty, after filtering; see below)
5. `ecs run-task` with those parameters.
6. `ecs wait tasks-running`; attempt to tail CloudWatch logs if the task
   definition declares an `awslogs` log group; `ecs wait tasks-stopped`; report
   the task's result and exit non-zero if it failed.

### Override filtering

EventBridge tolerates keys in the target `input` which are not part of the ECS
`TaskOverride`/`ContainerOverride` API shapes, and the infrastructure repo
relies on that (the `rds-s3-backups` target carries
`containerOverrides[].awslogs_stream_prefix`). `ecs run-task` rejects those keys
with `ParamValidation`, so the target input is filtered to the keys the ECS API
accepts before it is passed to `--overrides`:

- task overrides: `containerOverrides`, `cpu`, `ephemeralStorage`,
  `executionRoleArn`, `inferenceAcceleratorOverrides`, `memory`, `taskRoleArn`
- container overrides: `command`, `cpu`, `environment`, `environmentFiles`,
  `memory`, `memoryReservation`, `name`, `resourceRequirements`

Dropped keys are reported with `warning` so a target which relies on an
unsupported override is visible rather than silently altered.

### Log tailing caveat

EC2/bridge-mode service scheduled tasks may not log to CloudWatch with a
predictable stream. The command attempts to derive the log group from the task
definition's container definitions and tail it; if it cannot, it skips tailing,
reports the task ARN, and still waits for completion. This keeps the command
generic without failing on tasks that do not use `awslogs`.

## Error handling

- Missing `-i`/`-e` -> usage.
- No matching scheduled tasks found -> `err` + exit 1.
- `-t` value not found -> `err`, list available tasks, exit 1.
- Chosen rule has no ECS target -> `err` + exit 1.
- Target input is not a JSON object -> `err`, print the input, exit 1.
- `run-task` API call rejected (e.g. `ParamValidation`, `AccessDenied`) ->
  `err` + exit 1 rather than an unexplained `set -e` abort.
- `run-task` returns no task -> `err`, print each `failures[]` reason/detail,
  exit 1.
- `run-task` returns a task *and* failures -> `warning` with the failures, then
  continue.
- `tasks-running` waiter fails -> describe the task:
  - not `STOPPED` (waiter timed out) -> `err` with the task's status/stop
    reason/container reasons, exit 1.
  - `STOPPED` with `stopCode: TaskFailedToStart` or a non-zero container exit
    code -> `err` with the same detail, exit 1. This is the launch-failure case
    (image pull errors, missing secrets, no capacity).
  - `STOPPED` cleanly -> the task was too short-lived for the waiter; print its
    logs (without `--follow`) and treat it as a successful run.
- `tasks-stopped` waiter fails -> `err` with the task ARN, exit 1.
- Task stopped with a non-zero container exit code -> `err` with the stop
  reason and per-container exit codes/reasons, exit 1, so a failed run cannot
  be mistaken for a successful one.
- The log tail is stopped by an `EXIT` trap so it is not orphaned when the
  command exits early.

## Testing

`./test.sh` (shellcheck) must pass. Manual verification against a live infra
with an `s3-to-azure` job is expected but out of scope for automated tests.
