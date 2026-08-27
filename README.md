# Dalmatian Tools

CLI tools to help with working with Dalmatian

## Installation

1. Clone this repository locally

1. Install the dependencies

   ```
   brew bundle install
   ```

1. Add the dalmatian-tools `bin` directory to your `$PATH`

   To add the ability to run the `dalmatian` command, you will need to add the
   Dalmatian Tools `bin` directory to your `$PATH` variable

   Find the full path of Dalmatian Tools by changing directory into this
   repository, and run `pwd`. eg:

   ```
   $ cd ~/git-clones/dalmatian-tools
   $ pwd
   /Users/user/git-clones/dalmatian-tools
   ```

   Add this path, plus '/bin' to the '$PATH' variable, by modifying
   either the `~/.bashrc` or `~/.zshrc` file

   ```bash
   # ~/.bashrc or ~/.zshrc
   export PATH="$PATH:/<path-to-dalmatian-tools>/bin"
   ```

   The easiest way for this to take effect is to close and open your terminal application

   Or you can run `source ~/.bashrc` or `source ~/.zshrc` on all open terminals

1. Configure AWS SSO

  Dalmatian signs in with AWS IAM Identity Center. The configuration is written
  by `dalmatian setup`, and is shared by v1 and v2:

  ```
  $ dalmatian version -v 2
  $ dalmatian setup
  $ dalmatian version -v 1
  ```

  `dalmatian setup` is a v2 tool, and is what writes the AWS SSO configuration
  that v1 also reads, so switch back to v1 once it's done: the rest of this
  guide, and Dalmatian Tools by default, use v1.

  You only need to do this once. See
  [README-in-development.md](README-in-development.md) for what `dalmatian setup`
  asks for.

1. Login to dalmatian

  Run the `dalmatian login` command. It installs and updates the dependencies
  Dalmatian Tools needs, then signs you in with AWS SSO, opening your browser if
  your session has expired.

  ```
  $ dalmatian login
  Note: You must have a Dalmatian admin account in your organisation's AWS IAM Identity Center to use Dalmatian Tools

  ==> Updating brew packages ...
  ==> Installing AWS Session Manager Plugin into /Users/user/Applications/session-manager-plugin
  ==> Ensuring tfenv is configured ...
  ==> Checking AWS CLI is the correct version ...
  ==> Detected AWS CLI version: 2.36.22
  ==> Signing in with AWS SSO ...
  ==> Attempting AWS SSO login ...
  ==> You're already logged in. Your existing session will expire on 2026-08-13T22:15:31Z
  ==> Exporting AWS SSO credentials...
  ==> User ID: XXXXXXXXXXXXXXXXXXXXX:user
  ==> Account: XXXXXXXXXXXX
  ==> Arn:     arn:aws:sts::XXXXXXXXXXXX:assumed-role/AWSReservedSSO_admin_XXXXXXXXXXXXXXXX/user
  ==> Login success!
  ```

  Your session lasts about 8 hours. Any `dalmatian` command refreshes it for you
  when it expires, or you can run `dalmatian aws login` yourself.

  To use the credentials in your own shell, run this v1 command:

  ```
  $ eval "$(dalmatian aws export-credentials)"
  ```

### Deprecated: IAM user credentials

Before AWS SSO, Dalmatian v1 signed in with a long-lived IAM user access key and
a TOTP MFA secret, held GPG-encrypted in
`~/.config/dalmatian/credentials.json.enc`. That path still works, and is used
automatically if no AWS SSO configuration is found, but it is deprecated and
will be removed, though no removal date is set yet. If you see

```
[!] Warning: Dalmatian v1 is using a deprecated IAM user access key and MFA secret
```

run `dalmatian version -v 2 && dalmatian setup` to switch to AWS SSO.

## FAQ

### Why am I seeing "oathtool: base32 decoding failed: Base32 string is invalid"

This applies only to the deprecated IAM user credentials described above.

Probably you've entered your 6 digit MFA code rather than the underlying MFA
secret which is a long alphanumeric string. This secret is available:

- at the time you set up MFA in the AWS Console (Security Credentials | Manage MFA), and

- in 1Password if you're using that software to generate MFA codes. You need to
  go into 'edit' mode to view. You're looking for the string of letters and
  numbers after `?secret=`.

If you are using an 'app' such as Google Authenticator on your phone you may not
be able to access this initial secret without removing your MFA in the AWS
Console and setting it up afresh.

## Usage

### Help

  `dalmatian -h`

  ```
  $ dalmatian -h
  Usage: dalmatian
    SUBCOMMAND COMMAND     - dalmatian command to run
    SUBCOMMAND COMMAND -h  - show command help
      Or:
    -h                     - help
    -l
  ```

### List commands

  `dalmatian -l`

### Shell completion
**Bash (/bin/bash)**

Add the full path to the `support/bash-completion.sh` script to your `~/.bashrc` file

eg:

```
# ~/.bashrc

source /path/to/dalmatian-tools/support/bash-completion.sh
```

**Zsh (/bin/zsh)**

Add the full path to the `support/zsh-completion.sh` script to your `~/.zshrc` file

eg:

```
# ~/.zshrc

autoload -Uz +X compinit && compinit
autoload -Uz +X bashcompinit && bashcompinit
source /path/to/dalmatian-tools/support/zsh-completion.sh
```

### Environment Variables

- DALMATIAN_CONFIG_PATH
  Set a path to dalmatian.yml to override the use of the checkout used by the
  tools by default. Useful if bringing up a service or infrastructure whose
  config hasn't been merged in yet.

- DALMATIAN_FZF_ENABLED
  Set to 0 to disable fzf support for interactive selections. Defaults to 1.

- DALMATIAN_SKIP_UPDATE_PROMPT
  Set to 1 to skip the update prompt when there are local changes or the current
  version tag is newer than the remote. Useful when running a development
  version.

- DALMATIAN_SKIP_UPDATE_CHECK
  Set to 1 to skip the automatic update check that runs before every command.
  `dalmatian update` can still be run explicitly. Note that if the check can't
  reach Github (network failure, API rate limit, etc), it is skipped with a
  warning anyway.
