# `dalmatian service`

Commands for listing, deploying, inspecting logs, accessing containers, managing environment files, and running scheduled tasks for ECS services.

---

## `dalmatian service list-services`

**Safety:** Read-only

Outputs a JSON object describing all ECS services (or a single service) in an infrastructure environment, including desired/running container counts and S3 environment file location.

### Syntax

```bash
dalmatian service list-services -i <infrastructure> -e <environment> [-s <service_name>] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name (e.g. `staging`, `prod`).

### Optional options

- `-s <service_name>` — Filter to a single service.
- `-h` — Show help.

### Under the hood

Queries `ecs list-services`, `ecs describe-services`, and `ecs describe-task-definition` on the `<project>-<infrastructure>-<environment>-infrastructure` cluster, selecting the application container by name (`$service_name`) rather than index.

### Exit states

- `0` — JSON printed.
- Non-zero — Missing `-i`/`-e`, `-h`, or ECS API failure.

---

## `dalmatian service deploy`

**Safety:** Potentially disruptive

Triggers a CodePipeline execution for a service.

### Syntax

```bash
dalmatian service deploy -i <infrastructure> -e <environment> -s <service> [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.
- `-s <service>` — Service name.

### Under the hood

Calls `aws codepipeline start-pipeline-execution --name <project>-<infrastructure>-<environment>-ecs-service-<service>`.

### Exit states

- `0` — CodePipeline execution started.
- Non-zero — Missing `-i`/`-e`/`-s`, `-h`, or CodePipeline API failure.

---

## `dalmatian service logs`

**Safety:** Read-only

Fetches or tails CloudWatch Logs for a service.

### Syntax

```bash
dalmatian service logs -i <infrastructure> -e <environment> -s <service_name> [OPTIONS]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.
- `-s <service_name>` — Service name.

### Optional options

- `-S <since>` — Start of window: relative age (`30m`, `2h`, `1d`, `1w`) or any `date -d` format (defaults to `10m`).
- `-U <until>` — End of window, same formats as `-S` (defaults to now; cannot be combined with `-f`).
- `-p <filter_pattern>` — CloudWatch Logs filter pattern (e.g. `ERROR`).
- `-o <output_file>` — Write logs to a file instead of stdout (cannot be combined with `-f`).
- `-f` — Follow: stream new log events as they arrive.
- `-h` — Show help.

### Examples

```bash
dalmatian service logs -i myapp -e prod -s web -S 1h -p ERROR
dalmatian service logs -i myapp -e staging -s worker -f
```

### Exit states

- `0` — Logs printed/written.
- `1` — Missing `-i`/`-e`/`-s`, `-h`, `-f` combined with `-U` or `-o`, invalid date or `-S` not before `-U`, service or its same-named container not found, or the container does not log via `awslogs` (e.g. syslog/logspout services).
- Other non-zero — AWS CLI failure (its own exit code), or `130` when `-f` is interrupted with Ctrl-C.

---

## `dalmatian service container-access`

**Safety:** Potentially disruptive

Opens an interactive shell (or runs a command) inside a running ECS task container via ECS Exec.

### Syntax

```bash
dalmatian service container-access -i <infrastructure> -e <environment> -s <service_name> [OPTIONS]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.
- `-s <service_name>` — Service name.

### Optional options

- `-c <command>` — Command to run in the container (defaults to `/bin/bash`).
- `-n` — Run non-interactively (`--non-interactive`).
- `-h` — Show help.

### Under the hood

Finds the first running task for the service, selects the container named `$service_name` (avoiding sidecar containers), and invokes `aws ecs execute-command`.

### Exit states

- `0` — Session/command completed.
- Non-zero — Missing `-i`/`-e`/`-s`, `-h`, no running tasks found, container not found in task, or `ecs execute-command` failure.

---

## `dalmatian service get-environment-variables`

**Safety:** Sensitive

Streams a service's `.env` file from S3 directly into `$PAGER` (`less` by default) without writing secrets to disk.

### Syntax

```bash
dalmatian service get-environment-variables -i <infrastructure> -e <environment> -s <service> [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.
- `-s <service>` — Service name.

### Safety notes

- Output contains application secrets and credentials. Do not copy-paste into tickets or chat.

### Exit states

- `0` — Environment file streamed to `$PAGER`.
- Non-zero — Missing `-i`/`-e`/`-s`, `-h`, environment file does not exist in S3, or S3 access failure.

---

## `dalmatian service set-environment-variables`

**Safety:** Sensitive / Potentially disruptive

Downloads a service's `.env` file from S3 into a private temporary directory (`umask 077`, cleaned up on exit), opens it in `$EDITOR`, and uploads changes back to S3.

### Syntax

```bash
dalmatian service set-environment-variables -i <infrastructure> -e <environment> -s <service> [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.
- `-s <service>` — Service name.

### Safety notes

- **Prints plaintext secrets in diffs:** In non-quiet mode (`QUIET_MODE=0`), `set-environment-variables` prints a unified diff (`colordiff -u`) containing plaintext edited values and surrounding context lines to the terminal **before** prompting to upload. Even if you decline the upload, those values appear in terminal output, scrollback, and screen recordings (run with `-q` if you need to suppress diff output).
- **Overwrite risk on `head-object` failure or concurrent edits:** Any failed `s3api head-object` check (including expired SSO credentials, permission errors, or network failures—not only a genuinely missing object) triggers the creation prompt (`default: N`). Accepting starts from a blank local file and performs an unconditional `s3 cp`, overwriting any existing remote `.env` file. Normal edits also upload unconditionally without conflict detection, so concurrent remote edits can be overwritten.
- After uploading, prompts to redeploy the service. **The prompt defaults to yes**, so pressing Enter starts a `service deploy` (CodePipeline execution). If you decline, tasks keep the old values until the service is next deployed.

### Exit states

- `0` — `.env` updated in S3 (and optionally redeployed), no changes made in `$EDITOR`, or user declined creating/uploading.
- Non-zero — Missing `-i`/`-e`/`-s`, `-h`, or S3/editor failure.

---

## `dalmatian service run-scheduled-task`

**Safety:** Potentially disruptive

Triggers an on-demand ECS task run using the task definition and network configuration of an EventBridge scheduled task rule.

### Syntax

```bash
dalmatian service run-scheduled-task -i <infrastructure> -e <environment> [-t <task_name>] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.

### Optional options

- `-t <task_name>` — Scheduled task EventBridge rule name (if omitted, picks automatically when only one exists, or opens an `fzf`/numbered selector).
- `-h` — Show help.

### Exit states

- `0` — Scheduled task completed successfully, interactive picker cancelled/quit (`No scheduled task selected, quitting`), or final `describe-tasks` lookup returned no task (prints a warning that the result is unknown).
- Non-zero — Missing `-i`/`-e`, `-h`, no scheduled tasks found, invalid `-t` name, rule has no ECS target or non-object `Input`, `ecs run-task` failure, wait timeout (`ecs wait tasks-stopped`), or task/container failure.
