# Configuration & Lifecycle Commands

Top-level commands for setting up Dalmatian Tools, managing multiple installations, switching CLI versions, and updating the toolkit.

---

## `dalmatian setup`

**Safety:** Potentially disruptive

Configures a Dalmatian installation (either creating a new one or updating an existing one), writes backend Terraform `.vars` files, generates AWS SSO profiles, initialises the main account workspace, and runs `deploy account-bootstrap` (`terraform apply`) on `dalmatian-main`.

### Syntax

```bash
dalmatian setup [OPTIONS]
```

### Optional options

- `-n <installation_name>` — Name for this installation (defaults to the project name; must use lower-case letters, digits, `-`, and `_`, starting with a letter or digit).
- `-f <setup_filepath>` — Seed prompt defaults from a local `setup.json` file.
- `-u <setup_url>` — Seed prompt defaults from a hosted `setup.json` URL.
- `-b` — Enable bootstrap mode (also enabled when `DALMATIAN_BOOTSTRAP=true`). Passes `-d` to `aws account-init` and offers to run `dalmatian deploy account-bootstrap` on the main account.
- `-y` — Skip the confirmation prompt (and exports `DALMATIAN_ASSUME_YES=1` so chained state-bucket creation is also non-interactive).
- `-h` — Show help.

### Expected output

Displays a banner, prompts for project/SSO/backend/main-account values, prints a summary, asks for confirmation (`Continue? (y/N)`), and then outputs progress from `aws generate-config` and `aws account-init`, ending with:

```text
==> Setup complete!
```

### Safety notes

- **Runs `terraform apply` on `dalmatian-main`:** Even without `-b` (including when joining an existing project with `-f` or `-u`), `setup` unconditionally calls `aws account-init`, which runs `deploy account-bootstrap` (`terraform apply`) on `dalmatian-main`. Review the Terraform plan before confirming if there are pending changes on the main account.
- Re-running `dalmatian setup` with no `-n`, `-f`, or `-u` updates the active installation and refuses to change `project_name` (because `project_name` feeds every resource prefix hash).
- **The Terraform project name override prompt does not keep its current value on Enter:** Unlike the other prompts, pressing Enter clears any existing `terraform_project_name` override (used as a special case when spinning off a setup from an existing one), even though the current value is shown above it. If your installation—or a teammate's `setup.json` passed via `-f`/`-u`—carries an override, type it again at the prompt to preserve it; otherwise the `account-bootstrap` `terraform apply` that `setup` runs next will plan against the original `project_name` and may propose replacing resources.
- The first installation on a machine becomes the default automatically; later installations do not overwrite the default.

### Exit states

- `0` — Setup completed successfully, or cancelled at the `Continue? (y/N)` confirmation prompt (`Nothing written`).
- Non-zero — Invalid usage/flags, invalid installation name, missing `-f` file, mismatched `project_name` on an existing installation, blank template targeting an existing installation, or downstream AWS/Terraform failure.

### Under the hood

1. Stages answers in a temporary file until you confirm the summary.
2. Writes `~/.config/dalmatian/installations/<name>/setup.json`, `account-bootstrap-backend.vars`, and `infrastructure-backend.vars`, and creates `tmp/<name>/` under the repo checkout.
3. Runs `dalmatian aws generate-config` (which triggers `aws login`, `terraform-dependencies clone`, and `terraform-dependencies initialise`).
4. Runs `dalmatian aws account-init` for `dalmatian-main`.

### Examples

```bash
# Join an existing project from a teammate's setup.json
dalmatian setup -f ./setup.json

# Create a separate installation name for a project
dalmatian setup -n client-a -f ./setup.json

# Bootstrap a brand-new Dalmatian project
dalmatian setup -b
```

---

## `dalmatian installation`

**Safety:** Read-only (`list`), Potentially disruptive (`use`), Destructive (`remove`)

Manages multiple Dalmatian installations on a single machine.

### Syntax

```bash
dalmatian installation ACTION [OPTIONS]
```

### Actions & options

- `list` — List all installations on this machine (`*` marks the default).
- `use [<name>]` — Set `<name>` as the default installation. Omit `<name>` to pick interactively (`fzf` or numbered menu when `DALMATIAN_FZF_ENABLED=0`).
- `remove [-y] [<name>]` — Delete an installation's configuration directory (`~/.config/dalmatian/installations/<name>`) and Terraform working copies (`tmp/<name>`). Pass `-y` to skip the confirmation prompt.
- `-h` — Show help.

### Expected output

```text
$ dalmatian installation list
* example-project           example-project
  client-a                  client-a-platform
```

### Safety notes

- `installation remove` permanently deletes local installation config and Terraform working copies (it does **not** destroy AWS resources).
- The currently active default installation cannot be removed; switch to another default with `dalmatian installation use <other>` first.
- Use `DALMATIAN_INSTALLATION=<name>` to override the default for a single command or shell session.

### Exit states

- `0` — Action succeeded (`list` with zero or more installations, `use`, or `remove`), or `remove` was declined at the confirmation prompt (`Nothing removed`).
- `1` — Invalid action/flags, invalid or non-existent installation name, attempting to `remove` the default installation, or cancelling the interactive picker.

### Examples

```bash
dalmatian installation list
dalmatian installation use client-a
dalmatian installation remove old-project
```

---

## `dalmatian version`

**Safety:** Read-only (when viewing) / Potentially disruptive (when switching)

Displays or switches the active Dalmatian Tools command mode (`v1` legacy vs `v2` current).

### Syntax

```bash
dalmatian version [OPTIONS]
```

### Optional options

- `-v <set_version>` — Set the version number (e.g. `-v 2` or `-v 1`).
- `-s` — Output only the version string (e.g. `v2`).
- `-q` — Quiet mode.
- `-h` — Show help.

### Expected output

```text
$ dalmatian version
==> Dalmatian Tools v2
==> (Release: v0.47.0-1-g030974d)
==> The tooling available in v2 is to be used with infrastructures
==> deployed via dalmatian-tools
==> To use tooling for use with infrastructures launched with the dxw/dalmatian repo,
==> switch to 'v1' by running 'dalmatian version -v 1'
```

### Under the hood

Reads and writes `~/.config/dalmatian/version.json`.

### Exit states

- `0` — Version printed or updated.
- `1` — Invalid flags or `-h`.

---

## `dalmatian update`

**Safety:** Potentially disruptive

Checks GitHub for the latest Dalmatian Tools release and updates the local checkout and Homebrew dependencies if a newer tag is available.

### Syntax

```bash
dalmatian update [OPTIONS]
```

### Optional options

- `-f` — Force update (runs the update process even if already on the latest tag, and fails hard if GitHub cannot be reached).
- `-h` — Show help.

### Expected output

```text
==> Checking for newer version ...
==> Updating ...
```

### Safety notes

- Prompts before updating if tracked files have uncommitted changes or `HEAD` is ahead of the latest release tag (skipped with `DALMATIAN_SKIP_UPDATE_PROMPT=1`). Untracked files are ignored.
- Checks out `main`, pulls, checks out the latest release tag, runs `brew bundle`, reinstalls the Session Manager plugin, relinks `tfenv`, then re-clones the pinned Terraform working copies (`terraform-dependencies clone -I`) and refreshes the tfvars cache (`get-tfvars -n`) for the active installation.

### Exit states

- `0` — Already up to date, update succeeded, GitHub unreachable/rate-limited without `-f` (skips with warning), or local-changes prompt answered `Y` (or `DALMATIAN_SKIP_UPDATE_PROMPT=1`).
- Non-zero — Invalid flags/`-h` (`1`), GitHub unreachable when `-f` is passed (`1`), local-changes prompt answered `N` (`1`), or `git`/`brew`/child failure.
