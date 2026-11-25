# `dalmatian ecs`

Commands for accessing ECS container host EC2 instances and inspecting recent ECS service deployments.

---

## `dalmatian ecs ec2-access`

**Safety:** Potentially disruptive

Starts an AWS SSM Session Manager shell on an EC2 host belonging to an infrastructure environment's ECS cluster. Requires `session-manager-plugin`.

### Syntax

```bash
dalmatian ecs ec2-access -i <infrastructure> -e <environment> [OPTIONS]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.

### Optional options

- `-l` — List available EC2 instance IDs for the cluster and exit.
- `-I <instance_id>` — Specific EC2 instance ID (pass `-I ''` to pick interactively).
- `-c` — Choose the instance interactively (only prompts if more than one is found).

Without `-I` or `-c`, connects to the first instance listed for the cluster without prompting.
- `-h` — Show help.

### Under the hood

Filters running EC2 instances (`instance-state-code=16`) by tags `Infrastructure`, `Environment`, and `Project`.

### Exit states

- `0` — Session completed or `-l` listed instances.
- Non-zero — Missing `session-manager-plugin`, missing `-i`/`-e`, `-h`, no matching instances found, or SSM session failure.

---

## `dalmatian ecs list-deployments`

**Safety:** Read-only

Lists ECS service deployments from the last 7 days for a cluster (or a single service).

### Syntax

```bash
dalmatian ecs list-deployments -i <infrastructure> -e <environment> [-s <service_name>] [-d] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.

### Optional options

- `-s <service_name>` — Filter to a specific service.
- `-d` — Include the Deployment ID in output.
- `-h` — Show help.

### Exit states

- `0` — Deployments listed (up to 20 per service), or none found. Per-service API errors are suppressed, so a failing or misspelt `-s` service also returns `0` with no output for it.
- Non-zero — Missing `-i`/`-e`, `-h` (`1`), or failure listing services / resolving the profile (AWS CLI exit code).
