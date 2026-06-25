# Design Spec: AWS put-secret (v2)

## Overview
A new command to add an arbitrary secret/parameter to AWS SSM Parameter Store using the `v2` (AWS SSO-based) configuration and authentication. This command will output the Parameter's ARN so it can be captured and used elsewhere (e.g. in Terraform tfvars).

## Goals
- Add a `v2` version of the `put-secret` command at `bin/aws/v2/put-secret`.
- Ensure the secret is stored securely as a `SecureString` in AWS SSM Parameter Store.
- Automatically prefix parameter names as `/<infrastructure>/<environment>/<secret-name>`.
- Allow the user to input the secret value via a command line flag, standard input, or secure prompt.
- Default to standard KMS key `alias/aws/ssm` but support custom KMS key override.
- Output ONLY the parameter's ARN to stdout upon successful completion.

## Architecture
The command will be a bash script following the established `v2` AWS tool patterns.

### Key Components
- **Profile Resolution:** Uses `resolve_aws_profile` from `lib/bash-functions/resolve_aws_profile.sh`.
- **AWS Integration:** Uses `dalmatian aws run-command` to perform authenticated AWS CLI operations.

## Logic & Data Flow
1.  **Parse Arguments:** Parse `-i` (infrastructure), `-e` (environment), `-n` (secret name), `-v` (secret value), and `-k` (KMS key ID).
2.  **Validate Arguments:** Ensure `-i`, `-e`, and `-n` are all provided.
3.  **Resolve Profile:** Call `resolve_aws_profile -i $INFRASTRUCTURE_NAME -e $ENVIRONMENT` to get the AWS SSO profile name.
4.  **Format Parameter Name:**
    - Strip any leading slash from the provided `-n` value.
    - Format full path: `PARAMETER_NAME="/$INFRASTRUCTURE_NAME/$ENVIRONMENT/$SECRET_NAME"`.
5.  **Get Secret Value:**
    - If `-v` is provided, use its value.
    - If `-v` is omitted and stdin is NOT a TTY, read value from stdin.
    - If `-v` is omitted and stdin IS a TTY, prompt the user securely (`read -rs`).
6.  **Create/Update SSM Parameter:**
    - Execute `aws ssm put-parameter` with type `SecureString`, the resolved profile, the parameter name, and `--overwrite`.
    - If a custom KMS key was provided via `-k`, pass it as `--key-id`. Otherwise, use `alias/aws/ssm`.
7.  **Retrieve & Output ARN:**
    - Execute `aws ssm get-parameter` to retrieve the created parameter's ARN.
    - Print the ARN to `stdout`.

## Error Handling
- **Missing Arguments:** Show usage and exit if `-i`, `-e`, or `-n` are missing.
- **Profile Not Found:** `resolve_aws_profile` will handle error reporting if the profile doesn't exist.
- **SSM Failures:** If `aws ssm put-parameter` fails, propagate the exit status and error message to `stderr`.
- **Output Cleanliness:** Ensure all prompts, info/warning logs, and error messages are redirected to `stderr` so that stdout contains strictly the ARN.

## Testing Strategy
- **Manual Verification:**
    - Run `dalmatian aws put-secret -i <infra> -e <env> -n <secret_name> -v <value>`.
    - Verify that only the ARN is printed to stdout.
    - Verify with `aws ssm get-parameter` that the parameter exists, has the right path, type, and value.
- **Interactive Verification:**
    - Run without `-v` to check interactive prompting.
    - Run with piping (e.g. `echo "piped-value" | dalmatian aws put-secret ...`) to verify stdin reading.
- **Negative Tests:**
    - Run with missing arguments to check usage output.
