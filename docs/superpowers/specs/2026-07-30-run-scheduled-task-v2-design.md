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
   - `EcsParameters.NetworkConfiguration` (if present) ->
     `--network-configuration`
   - `Input` -> `--overrides` (only if non-empty)
5. `ecs run-task` with those parameters.
6. `ecs wait tasks-running`; attempt to tail CloudWatch logs if the task
   definition declares an `awslogs` log group; `ecs wait tasks-stopped`.

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
- No task returned from `run-task` -> `err` + exit 1.

## Testing

`./test.sh` (shellcheck) must pass. Manual verification against a live infra
with an `s3-to-azure` job is expected but out of scope for automated tests.
