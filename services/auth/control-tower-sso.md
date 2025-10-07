# Using Control Tower + SSO with CLI

In Control Tower + AWS SSO (IAM Identity Center) environments, use temporary credentials via SSO.

## Prerequisites

AWS CLI v2 must be installed.

## Configuration

```sh
# Interactive setup
aws configure sso
# Or configure individually
aws configure set sso_session corp-sso --profile dev
# Or create `~/.aws/config` directly
```

Example SSO configuration in `~/.aws/config`:

```~/.aws/config
[profile dev]
sso_session = my-sso
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = ap-northeast-1
output = json

[profile prod]
sso_session = my-sso
...

[sso-session my-sso]
sso_start_url = https://<your-domain>.awsapps.com/start
sso_region = ap-northeast-1
sso_registration_scopes = sso:account:access
```

For a single account, you can also set it as the default:

```~/.aws/config
[default]
sso_session = my-sso
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = ap-northeast-1
output = json
```

### Login (SSO Authentication)

On first use, a browser will open and prompt you to log in via the Control Tower/SSO interface (including ID, password, and MFA).

Once completed, the CLI creates a token cache and automatically retrieves temporary credentials thereafter.
(Re-login is only required when tokens expire.)

```sh
aws sso login --sso-session my-sso
# Or
aws sso login --profile dev
```

### Running Commands with Profile Option

```sh
aws sts get-caller-identity --profile dev
```

### Running Commands with AWS_PROFILE Environment Variable

```sh
export AWS_PROFILE=dev
# Profile can be omitted from subsequent commands
aws sts get-caller-identity
```

## Explicitly Retrieving Temporary Credentials (Access Key Format)

You can retrieve temporary AccessKeyId / SecretAccessKey / SessionToken.

```sh
aws sts get-caller-identity --profile dev
aws configure export-credentials --profile dev
```
