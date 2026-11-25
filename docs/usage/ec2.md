# `dalmatian ec2`

Commands for opening AWS Session Manager shells and port-forwarding tunnels to EC2 instances.

> [!NOTE]
> All `dalmatian ec2` commands require the AWS `session-manager-plugin` binary to be installed on your `$PATH`.

---

## `dalmatian ec2 shell` (alias: `dalmatian ec2 access`)

**Safety:** Potentially disruptive

Starts an interactive AWS SSM Session Manager shell on a running EC2 instance.

### Syntax

```bash
dalmatian ec2 shell (-i <infrastructure> -e <environment> | -a <account> | -p <profile>) [-l] [-I <instance_id>] [-h]
```

### Target options (choose one)

- `-i <infrastructure>` + `-e <environment>` — Resolve account profile from infrastructure and environment.
- `-a <account>` — Full Dalmatian account workspace (`<account_id>-<region>-<account_name>`, e.g. `210987654321-eu-west-2-client-prod`), not the friendly AWS profile name.
- `-p <profile>` — Explicit AWS SSO profile name.

### Optional options

- `-l` — List running EC2 instance IDs and exit.
- `-I <instance_id>` — Target EC2 instance ID. If omitted, opens an interactive picker when multiple instances are running, or connects automatically without prompting when only one instance is running.
- `-h` — Show help.

### Safety notes

- `-i`/`-e` only resolve the AWS account profile; instances are **not** filtered by infrastructure or environment tags (unlike `dalmatian ecs ec2-access`). All running instances in the account/region are eligible, so omitting `-I` when only one instance is running can connect to a different environment's host without prompting.

### Exit states

- `0` — Session completed or `-l` listed instances.
- Non-zero — Missing `session-manager-plugin`, missing target flags/`-h`, no running instances found, or SSM session failure.

---

## `dalmatian ec2 port-forward`

**Safety:** Potentially disruptive

Forwards a local TCP port to a port on a running EC2 instance via AWS Session Manager (`AWS-StartPortForwardingSession`).

### Syntax

```bash
dalmatian ec2 port-forward -i <infrastructure> -e <environment> -R <remote_port> -L <local_port> [-I <instance_id>] [-h]
dalmatian ec2 port-forward -i <infrastructure> -e <environment> -l
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.
- `-R <remote_port>` — Remote port on the EC2 instance (not required with `-l`).
- `-L <local_port>` — Local port to bind on your machine (not required with `-l`).

### Optional options

- `-l` — List running EC2 instance IDs and exit.
- `-I <instance_id>` — Target EC2 instance ID. If omitted, opens an interactive picker when multiple instances are running, or selects a sole running instance automatically without prompting.
- `-h` — Show help.

### Safety notes

- `-i`/`-e` only resolve the AWS account profile; instances are **not** filtered by infrastructure or environment tags (unlike `dalmatian ecs ec2-access`). All running instances in the account/region are eligible.

### Exit states

- `0` — Port-forwarding session closed or `-l` listed instances.
- Non-zero — Missing `session-manager-plugin`, missing required flags/`-h`, no running instances found, or SSM session failure.
