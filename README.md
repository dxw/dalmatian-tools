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
   /Users/alex/git-clones/dalmatian-tools
   ```

   Add this path, plus '/bin' to the '$PATH' variable, by modifying
   either the `~/.bashrc` or `~/.zshrc` file

   ```bash
   # ~/.bashrc or ~/.zshrc
   export PATH="$PATH:/<path-to-dalmatian-tools>/bin"
   ```

   The easiest way for this to take effect is to close and open your terminal application

   Or you can run `source ~/.bashrc` or `source ~/.zshrc` on all open terminals

1. Login to dalmatian

  Run the `dalmatian login` command

  You can find your AWS Access Key and Secret Key in the AWS console by heading
  to the [IAM users list](https://console.aws.amazon.com/iamv2/home#/users),
  choosing your `dalmatian-user-admin`, and selecting the "Security credentials"
  tab. You will need to create a new Access Key. *Do not close this dialog*
  until you have successfully logged in, as this is the only time you can view
  your Secret Key.

  When prompted for your MFA secret, this is _not_ the six numbers from 2FA.
  Instead, you will need the secret key used to generate this. See below for the
  FAQ if you don't know how to get this.

  ```
  $ dalmatian login
  Note: You must have a Dalmatian Admin account to use Dalmatian Tools

  For added security, your credentials and MFA secret will be
  encrypted with GPG

  Email associated with GPG key: alex@example.com
  AWS Access Key ID: XXXXXXXXXXXXXXXXXXXX
  AWS Secret Access Key:
  AWS MFA Secret:
  ==> Checking credentials...
    User ID: XXXXXXXXXXXXXXXXXXXXX
    Account: XXXXXXXXXXXX
    Arn:     arn:aws:iam::XXXXXXXXXXXX:user/dalmatian_admins/<user-name>
  ==> Saving configuration settings in /Users/alex/.config/dalmatian/config.json ...
  ==> Storing credentials in /Users/alex/.config/dalmatian/credentials.json.enc ...
  ==> Attempting MFA...
  ==> Storing MFA credentials in /Users/alex/.config/dalmatian/mfa_credentials.json
  ==> Login success!
  ```

  Once you're signed in you can safely close the AWS Access Key dialog.

## FAQ

### Why am I seeing "oathtool: base32 decoding failed: Base32 string is invalid"

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
