# Component-Targeted Deploys — Design

Date: 2026-07-21
Repo: `dalmatian-tools`
Related repo (read-only for this work): `terraform-dxw-dalmatian-infrastructure`

## Problem

`dalmatian deploy infrastructure` selects a Terraform workspace
(`<account_id>-<region>-<dalmatian_account>-<infrastructure_name>-<environment>`)
and runs a full `terraform apply` over the entire monolithic root module of
`terraform-dxw-dalmatian-infrastructure`. There are no submodules, no `-target`
usage, and one flat state per environment. A single environment commonly
expands to hundreds or thousands of resources.

Consequence: **noisy plans.** A change intended for one service produces a plan
polluted by unrelated cross-domain churn, out-of-band drift, shared-locals
ripple, and perpetual/forced diffs. Reviewing a focused change is hard because
the diff spans the whole environment.

## Goal

Let an operator scope a plan/apply to one or more **components** (logical
domains) so the reviewed and applied diff is limited to that component. This
directly reduces the noisy-plan problem.

## Constraints / Appetite

- **No changes to the `terraform-dxw-dalmatian-infrastructure` repo.** No
  modularisation, no `moved` blocks, no state splitting.
- Implementation is confined to `dalmatian-tools`.
- Targeting granularity is **by domain/component** (not per-service name, not
  raw passthrough).

## Known limitation (accepted, must be documented in the tool)

`terraform -target` still refreshes the full state, so drift *detection* is not
suppressed. What it changes is the *diff that is planned and applied* — that is
scoped to the targeted resources. This satisfies the noisy-plan goal but does
NOT eliminate drift elsewhere. The tool must warn that a periodic untargeted
plan is still required to catch drift outside the targeted component.

## Architecture

Add an optional, repeatable `-c <component>` flag to
`bin/deploy/v2/infrastructure`. When present:

1. Resolve each `-c` value against a new static data file
   `data/terraform-components.json`.
2. Expand each component to its list of Terraform resource **base addresses**.
3. Convert each address into a `-target=<address>` argument.
4. Append those `-target=` args to the existing `OPTIONS` array that is already
   passed through to `terraform-dependencies run-terraform-command`.

Everything else is unchanged: workspace selection/cycling, the layered
`-var-file` stack, and the `-p` / `-o` / `-s` / `-N` flags all behave as today.
When `-c` is absent, behaviour is identical to the current full-environment
deploy.

### Why base addresses (not fully-keyed addresses)

Terraform `-target` accepts a base resource address such as
`aws_ecs_service.infrastructure_ecs_cluster_service` and targets **all
instances** of that `for_each`/`count` resource. The data file therefore lists
one entry per resource block per domain — it does NOT need to enumerate every
map key (service name, db name, bucket name, etc.). This keeps the mapping
stable as services are added/removed.

### Data flow

```
deploy infrastructure -c ecs-service -c rds -e prod ...
  -> resolve components against data/terraform-components.json
  -> read .targets[] for each selected component (jq)
  -> build -target=<addr> args
  -> append to existing OPTIONS array
  -> (existing) workspace select
  -> run-terraform-command
  -> terraform apply -target=... -target=... -var-file=... [--auto-approve]
```

## Components

### 1. `data/terraform-components.json`

Maps component name -> description + list of resource base addresses.

```json
{
  "ecs-service": {
    "description": "ECS services and everything they own (task defs, roles, ALB, target groups, CloudFront, build pipeline, ECR, blue/green, scheduled tasks, WAF).",
    "targets": [
      "aws_ecs_service.infrastructure_ecs_cluster_service",
      "aws_ecs_task_definition.infrastructure_ecs_cluster_service"
    ]
  },
  "rds": {
    "description": "RDS instances and Aurora clusters and their supporting resources.",
    "targets": [
      "aws_db_instance.infrastructure_rds",
      "aws_rds_cluster.infrastructure_rds"
    ]
  },
  "vpc":         { "description": "...", "targets": ["aws_vpc.infrastructure"] },
  "elasticache": { "description": "...", "targets": [] },
  "s3":          { "description": "...", "targets": [] },
  "route53":     { "description": "...", "targets": [] },
  "lambda":      { "description": "...", "targets": [] }
}
```

The final component set and exhaustive `targets` lists are produced during
implementation by enumerating the resource blocks in the corresponding
`*-infrastructure-*.tf` / `s3-*.tf` / etc. files. Component set to implement:
`ecs-service`, `rds`, `vpc`, `elasticache`, `s3`, `route53`, `lambda`,
`cloudformation`, `utilities`, `bastion`.

**Accuracy requirement:** each component's `targets` must include the full set
of resource blocks in that domain. An incomplete list yields an incomplete or
broken targeted plan. This is the primary maintenance risk and is mitigated by
the lint step below.

### 2. `bin/deploy/v2/infrastructure` changes

- New `-c <component>` in `getopts`, accumulated into a `COMPONENTS` array
  (repeatable; comma-separated also accepted and split).
- Validation: each component must be a key in `terraform-components.json`;
  otherwise hard error listing valid component names.
- Build `TARGET_OPTIONS`: for each selected component, read `.targets[]` via
  `jq`, prefix each with `-target=`, append to the existing `OPTIONS` array so
  it flows through the unchanged workspace-select -> run-terraform-command path.
- **Confirm + warn** (unless `-N`): before apply, print the expanded `-target`
  list, print the standard Terraform "`-target` is intended for exceptional
  use" warning, recommend a follow-up untargeted plan, and prompt `y/n`.
- Update `usage()` to document `-c`.

### 3. Component listing + drift lint

- Listing: invoking with an unknown component (or a dedicated helper) prints the
  available components and their descriptions, read from the JSON.
- Lint/validate path (documented; runnable manually and in CI): run
  `terraform state list` for a selected workspace and flag any component target
  base address that matches **zero** addresses in state. This catches the static
  file drifting from the TF repo (renamed/removed resources).

## Error handling

- Unknown component -> hard error listing valid names, non-zero exit.
- Missing/empty `terraform-components.json` -> hard error.
- `-c` combined with all-workspaces cycling -> allowed; the confirm prompt shows
  the target expansion per workspace before each apply.

## Testing

Follow the existing `test.sh` / `act` conventions in the repo.

- Assert the script emits the correct set of `-target=` args for a given `-c`
  combination (mock `run-terraform-command` to echo its received args).
- Assert an unknown component exits non-zero and lists valid components.
- Add a fixture `terraform-components.json` for the tests.
- Assert absence of `-c` produces no `-target=` args (unchanged full deploy).

## Out of scope

- Per-service-name targeting, raw `-target` passthrough.
- Any Terraform repo restructuring (modules, `moved`, state splitting).
- Suppressing drift detection.
