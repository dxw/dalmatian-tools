# `dalmatian terraform-dependencies`

Commands for managing the local Terraform working copies (`account-bootstrap` and `infrastructure`), S3-backed `.tfvars` caches, import blocks, and raw Terraform invocations.

---

## `dalmatian terraform-dependencies clone`

**Safety:** Potentially disruptive (replaces local Terraform working copies under `tmp/<installation>/`)

Clones the `terraform-dxw-dalmatian-account-bootstrap` and `terraform-dxw-dalmatian-infrastructure` repositories into the active installation's `tmp/` directory.

### Syntax

```bash
dalmatian terraform-dependencies clone [OPTIONS]
```

### Optional options

- `-a <account-bootstrap-repo-version>` — Override tag/branch for `account-bootstrap`.
- `-i <infrastructure-repo-version>` — Override tag/branch for `infrastructure`.
- `-I` — Run `dalmatian terraform-dependencies initialise` after cloning.
- `-y` — Create the Terraform state bucket without prompting if missing (used with `-I`).
- `-h` — Show help.

### Exit states

- `0` — Repositories cloned (and initialised if `-I` passed).
- Non-zero — Invalid flags/`-h`, `git clone` failure, or `initialise` failure.

---

## `dalmatian terraform-dependencies initialise`

**Safety:** Potentially disruptive (may create the S3 Terraform state bucket if missing, or apply missing versioning/encryption/public-access-block settings to an existing one)

Ensures the Terraform state S3 bucket exists (offering to create it with versioning, encryption, and public access block) and runs `terraform init` for both `account-bootstrap` and `infrastructure`.

### Syntax

```bash
dalmatian terraform-dependencies initialise [OPTIONS]
```

### Optional options

- `-r` — Pass `-reconfigure` to `terraform init`.
- `-u` — Pass `-upgrade` to `terraform init`.
- `-y` — Create the Terraform state bucket without asking if it is missing.
- `-h` — Show help.

### Exit states

- `0` — State bucket verified/created and `terraform init` succeeded for both projects.
- Non-zero — Invalid flags/`-h` (`1`), state bucket creation or settings repair declined or failed (`1`), or `terraform init` failed (Terraform's exit code).

---

## `dalmatian terraform-dependencies get-tfvars`

**Safety:** Potentially disruptive (modifies local `.cache/tfvars/`)

Downloads `.tfvars` files from the project's S3 tfvars bucket (`<project_hash>-tfvars`) into the installation's local cache, or seeds from templates if the bucket does not exist yet. Without `-n` it is interactive: it offers (default yes) to create a tfvars file for each workspace that lacks one, opening `$EDITOR`. It rewrites `project_name` in `000-terraform.tfvars`, rewrites the tfvars-paths file, and finishes by running `clean-tfvars-cache` (see the warning there).

### Syntax

```bash
dalmatian terraform-dependencies get-tfvars [-n] [-h]
```

### Optional options

- `-n` — Only download new `.tfvars` files, with two overwrite exceptions:
  1. When S3 has a newer `LastModified` timestamp than the local file, the remote file overwrites the local copy.
  2. When the tfvars S3 bucket does not exist, or when `head-object` for `000-terraform.tfvars` returns empty (including on access/network error), local `000-terraform.tfvars` is overwritten with just `project_name` and `aws_region`.
- `-h` — Show help.

### Exit states

- `0` — `.tfvars` cache updated (or seeded from templates on a new project where the S3 bucket returns `404`).
- Non-zero — Invalid flags/`-h` (`1`), or a failed bucket check or `aws s3 cp` download (AWS CLI exit code). Per-file existence checks swallow errors, so an unreachable object is treated as absent rather than failing.

---

## `dalmatian terraform-dependencies view-tfvars`

**Safety:** Potentially disruptive (can overwrite the cached file from S3)

Displays the cached `.tfvars` file for a selected `account-bootstrap` or `infrastructure` workspace.

### Syntax

```bash
dalmatian terraform-dependencies view-tfvars [-a <dalmatian_account> | -i <infrastructure_account>] [-h]
```

### Optional options

- `-a <dalmatian_account>` — Account bootstrap workspace name.
- `-i <infrastructure_account>` — Infrastructure workspace name.
- `-h` — Show help.

If neither `-a` nor `-i` is provided, prompts you to choose Account Bootstrap or Infrastructure and pick a workspace via `fzf` (or numbered menu).

### Exit states

- `0` — `.tfvars` file displayed, diff shown (menu option 3), or the file does not exist in S3 (reported, nothing displayed).
- `1` — Invalid flags/`-h`, invalid project selection, or cancelled `fzf` picker.

---

## `dalmatian terraform-dependencies set-tfvars`

**Safety:** Potentially disruptive

Edits a workspace's `.tfvars` file in `$EDITOR` (checking for remote S3 diffs first), runs `terraform plan` on the selected workspace, prompts to deploy it, and—if deployed and not explicitly targeting `dalmatian-main`—runs an auto-approved `deploy account-bootstrap -N` on `dalmatian-main` to upload tfvars to S3. Declining the deployment prompt exits before that upload step, so editing alone does not publish changes to S3.

### Syntax

```bash
dalmatian terraform-dependencies set-tfvars [-a <dalmatian_account> | -i <infrastructure_account>] [-h]
```

### Optional options

- `-a <dalmatian_account>` — Account bootstrap workspace name.
- `-i <infrastructure_account>` — Infrastructure workspace name.
- `-h` — Show help.

### Exit states

- `0` — Deploy run and tfvars uploaded; deploy prompt declined (nothing uploaded); or menu option 6 (abort).
- Non-zero — Invalid flags/`-h`, invalid project selection, cancelled picker, EOF at the diff menu, or a failed Terraform plan/apply/upload (Terraform's own exit code).

> [!WARNING]
> The "run the deploy now?" prompt defaults to **yes**. Accepting it applies the workspace and then runs an auto-approved `terraform apply` on `dalmatian-main`, which applies any other pending changes there too.

---

## `dalmatian terraform-dependencies set-global-tfvars`

**Safety:** Potentially disruptive

Edits the global `account-bootstrap` or `infrastructure` `.tfvars` file in `$EDITOR` (checking remote S3 for conflicts first), **immediately runs an auto-approved `deploy account-bootstrap -N` on the main Dalmatian account to upload tfvars**, and then prompts whether to deploy across all accounts. Note that the main-account Terraform apply occurs before—and regardless of whether you accept—the all-accounts deployment prompt.

### Syntax

```bash
dalmatian terraform-dependencies set-global-tfvars (-a | -i) [-h]
```

### Required options (choose one)

- `-a` — Edit global `account-bootstrap` tfvars.
- `-i` — Edit global `infrastructure` tfvars.

### Exit states

- `0` — Main-account apply completed (whether or not the file was edited, including when the create prompt was declined) and the all-accounts prompt answered.
- Non-zero — Missing `-a`/`-i`, `-h` (`1`), or S3/editor/Terraform failure.

---

## `dalmatian terraform-dependencies clean-tfvars-cache`

**Safety:** Potentially disruptive (deletes stale local `.tfvars` cache files)

Removes local `100-*.tfvars` and `200-*.tfvars` cache files whose corresponding Terraform workspaces no longer exist.

### Syntax

```bash
dalmatian terraform-dependencies clean-tfvars-cache [-h]
```

### Exit states

- `0` — Stale cache files removed (or none found).
- `1` — Invalid flags/`-h`.

> [!WARNING]
> If listing the Terraform workspaces fails (for example an expired SSO session), this currently deletes **every** cached `100-*`/`200-*` tfvars file and still exits `0` ([#587](https://github.com/dxw/dalmatian-tools/issues/587)). `get-tfvars` runs it automatically.

---

## `dalmatian terraform-dependencies create-import-file`

**Safety:** Potentially disruptive (writes a local `.tf` file)

Interactively prompts for Terraform `to` resource addresses and `id` values to generate a `terraform import` block file (`import.tf`).

### Syntax

```bash
dalmatian terraform-dependencies create-import-file -o <output-location> [-h]
```

### Required options

- `-o <output-location>` — Path where the new `import.tf` file should be written (must not already exist).

### Exit states

- Runs in an interactive loop appending `import` blocks until interrupted (`Ctrl-C`); exits `1` if `-o` is missing or already exists.

---

## `dalmatian terraform-dependencies link-import-file`

**Safety:** Potentially disruptive (symlinks `dalmatian-import.tf` into working copy)

Symlinks an `import.tf` file into the `account-bootstrap` and/or `infrastructure` Terraform working directory as `dalmatian-import.tf`.

### Syntax

```bash
dalmatian terraform-dependencies link-import-file [-a <account_bootstrap_import_file>] [-i <infrastructure_import_file>] [-h]
```

### Options

- `-a <account_bootstrap_import_file>` — Path to import file for `account-bootstrap`.
- `-i <infrastructure_import_file>` — Path to import file for `infrastructure`.

### Exit states

- `0` — Symlink(s) created (note: if a specified file does not exist, prints an error message and still exits `0`).
- `1` — Neither `-a` nor `-i` provided, or `-h`.

---

## `dalmatian terraform-dependencies run-terraform-command`

**Safety:** Potentially disruptive / Sensitive (depends on the Terraform command executed; non-quiet mode also prints environment values)

> [!WARNING]
> In non-quiet mode, the wrapper prints all `AWS_*` and `TF_*` environment values, including inherited `TF_VAR_*` secrets, even for commands such as `workspace list`. Pass `-q` to suppress this environment dump and avoid sharing output containing secrets. Terraform's own output is not redacted by `-q`.

Executes an arbitrary Terraform command inside either the `account-bootstrap` or `infrastructure` working directory, automatically injecting backend config on `init` and tfvars on `plan`/`apply`/`console`/`import`.

### Syntax

```bash
dalmatian terraform-dependencies run-terraform-command -c "<command>" (-a | -i) [-q] [-h]
```

### Required options

- `-c <command>` — Quoted Terraform command to run (leading `terraform ` is optional).
- `-a` or `-i` — Target `account-bootstrap` (`-a`) or `infrastructure` (`-i`).

### Optional options

- `-q` — Quiet mode (only outputs Terraform command output).
- `-h` — Show help.

### Examples

```bash
dalmatian terraform-dependencies run-terraform-command -i -c "workspace list"
dalmatian terraform-dependencies run-terraform-command -a -c "state list" -q
```

### Exit states

- Propagates the exit code of `terraform` (`1` on missing `-c` or `-a`/`-i`, `-h`, or missing Terraform working directory).
