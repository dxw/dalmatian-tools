## Installation

1. Clone this repository locally

1. Install the dependencies

   ```bash
   brew bundle install
   ```

1. Add the dalmatian-tools `bin` directory to your `$PATH`

   To add the ability to run the `dalmatian` command, you will need to add the
   Dalmatian Tools `bin` directory to your `$PATH` variable.

   Find the full path of Dalmatian Tools by changing directory into this
   repository, and run `pwd`. eg:

   ```bash
   $ cd ~/git-clones/dalmatian-tools
   $ pwd
   /Users/alex/git-clones/dalmatian-tools
   ```

   Add this path, plus `/bin`, to the `$PATH` variable by modifying
   either `~/.bashrc` or `~/.zshrc`:

   ```bash
   # ~/.bashrc or ~/.zshrc
   export PATH="$PATH:/<path-to-dalmatian-tools>/bin"
   ```

   Close and reopen your terminal application, or run `source ~/.bashrc` / `source ~/.zshrc` in open terminals.

1. Set up Dalmatian Tools (v2 / AWS SSO — Recommended)

   **Prerequisites:**
   - An AWS IAM Identity Center (SSO) user with Administrative access to at least the main Dalmatian account.
   - GitHub SSH access configured (`git@github.com:...`) so `dalmatian` can clone the Terraform dependency repositories.

   First, switch Dalmatian Tools to `v2` (fresh installations default to `v1`, where `setup` is unavailable):

   ```bash
   dalmatian version -v 2
   ```

   If you are joining an existing Dalmatian project, ask a teammate for the project's `setup.json` (stored on their machine at `~/.config/dalmatian/installations/<name>/setup.json`) or a hosted setup URL (`-u`), then run:

   ```bash
   dalmatian setup -f setup.json
   ```

   If you are starting a brand-new Dalmatian project with no existing `setup.json`, run `dalmatian setup` (or `dalmatian setup -b` to bootstrap the main account).

   Before continuing, select the installation you just configured with `dalmatian installation use <installation_name>` (use the installation name printed by `setup`). Setup preserves an existing default when adding another installation. If `DALMATIAN_INSTALLATION` is set in your shell, update or unset it too, because it overrides that default for both v1 and v2 commands.

   Then authenticate via AWS IAM Identity Center (SSO):

   ```bash
   dalmatian aws login
   ```

   See [Configuration & Lifecycle Commands](./usage/configure.md) for multi-installation and bootstrap options.

   If you also need to operate **v1 (legacy)** infrastructure, switch back to v1 after completing SSO setup; `dalmatian login` will prefer your SSO session automatically:

   ```bash
   dalmatian version -v 1
   dalmatian login
   ```

### Deprecated v1 Fallback: IAM User Access Key & MFA

> [!WARNING]
> Configuring v1 with long-lived IAM User access keys and an MFA secret is **deprecated**. Use AWS SSO (`dalmatian version -v 2 && dalmatian setup`) unless you are maintaining legacy v1 access without SSO.

If SSO is not configured when you run `dalmatian login` in v1 mode, it will prompt for GPG encryption, an IAM Access Key ID, Secret Access Key, and MFA secret.

You can find your AWS Access Key and Secret Key in the AWS console by heading to the [IAM users list](https://console.aws.amazon.com/iamv2/home#/users), choosing your `dalmatian-user-admin`, and selecting the "Security credentials" tab. You will need to create a new Access Key. *Do not close this dialog* until you have successfully logged in, as this is the only time you can view your Secret Key.

When prompted for your MFA secret, this is _not_ the six numbers from 2FA. Instead, you will need the base32 secret key used to generate them (see the [FAQ](./faq.md#why-am-i-seeing-oathtool-base32-decoding-failed-base32-string-is-invalid)).
