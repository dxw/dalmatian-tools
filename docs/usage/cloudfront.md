# `dalmatian cloudfront`

Commands for invalidating CloudFront caches and downloading CloudFront access logs.

---

## `dalmatian cloudfront clear-cache`

**Safety:** Potentially disruptive (cache invalidation increases origin load)

Creates a CloudFront invalidation for a service's distribution and waits until it completes.

### Syntax

```bash
dalmatian cloudfront clear-cache -i <infrastructure> -s <service_name> -e <environment> [-P "<paths>"] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-s <service_name>` — Service name (matches distribution origin ID `<service_name>-default`).
- `-e <environment>` — Environment name.

### Optional options

- `-P <path>` — Path to invalidate (defaults to `/*`). Note: although `-h` says "space separated list of paths", the script passes `--paths "$PATHS"` as a single quoted argument, so space-separated values become one path containing spaces; pass a single path per invocation.
- `-h` — Show help.

### Exit states

- `0` — Invalidation created and completed.
- Non-zero — Missing `-i`/`-s`/`-e`, `-h`, distribution not found (`1`), or CloudFront API failure.

---

## `dalmatian cloudfront logs`

**Safety:** Read-only (downloads log files locally)

Syncs CloudFront access logs for a service from S3 (`s3://<prefix_hash>-logs/cloudfront/infrasructure-ecs-cluster-service/<service_name>`) to a local directory.

### Syntax

```bash
dalmatian cloudfront logs -i <infrastructure> -s <service_name> -e <environment> [-p <pattern>] [-d <directory>] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-s <service_name>` — Service name.
- `-e <environment>` — Environment name.

### Optional options

- `-p <pattern>` — Filename substring filter (e.g. `2026-11-24`).
- `-d <directory>` — Local destination directory (defaults to `/tmp/<infrastructure>-<service_name>-<environment>-cloudfront-logs`).
- `-h` — Show help.

### Exit states

- `0` — Logs synced to local directory.
- Non-zero — Missing `-i`/`-s`/`-e`, `-h`, or S3 sync failure.
