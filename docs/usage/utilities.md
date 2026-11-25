# `dalmatian utilities`

Commands for running interactive or one-off tasks in the infrastructure utilities ECS container.

---

## `dalmatian utilities run-command`

**Safety:** Potentially disruptive (Destructive with `-s`, which runs SQL with the RDS admin credentials)

Runs a command or opens an interactive shell in the environment's utilities container (targeting an RDS instance).

### Syntax

```bash
dalmatian utilities run-command -i <infrastructure> -e <environment> -r <rds_name> (-c "<command>" | -I) [OPTIONS]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.
- `-r <rds_name>` — RDS name. **Required**: the utilities task definition, security group and subnets are looked up from it, so the command fails without it.
- `-c <command>` or `-I` — Command to execute (`-c`), or start an interactive shell (`-I`).

### Optional options

- `-s` — Run the command against the RDS instance rather than just the container.
- `-R <result_file>` — Write task outcome (`exited <n>` or `never-ran`) to a file (cannot be combined with `-I`).
- `-D <keep_alive_delay>` — Seconds to check for `mysql`/`psql`/`bash` processes before exiting an interactive shell (default `60`).
- `-M <keep_alive_maximum_lifetime>` — Maximum container lifetime in seconds for an interactive shell (default `600`).
- `-h` — Show help.

### Exit states

- `0` — Interactive shell exited cleanly, or non-interactive command returned `0`.
- `1` (or container exit status) — Missing required flags, `-h`, `-R` combined with `-I`, utilities task failed to start, or command inside container failed.
