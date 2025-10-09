# AWS Authentication Service

A comprehensive, extensible authentication service for AWS utilities with plugin architecture and advanced configuration management.

## Overview

The AWS Authentication Service provides a unified interface for managing various AWS authentication methods with built-in extensibility through a plugin system, configuration management, and hook mechanisms.

## Features

- **🔐 Multiple Authentication Methods**: SSO, Access Keys, Role Assumption, Instance Profiles, Web Identity, Environment Variables
- **🔌 Plugin Architecture**: Easy addition of custom authentication handlers
- **⚙️ Configuration Management**: Centralized configuration with per-handler settings
- **🪝 Hook System**: Pre/post authentication processing with priority-based execution
- **📊 Registry System**: Dynamic handler discovery and management
- **🛡️ Security Features**: Secure credential handling and validation
- **📝 Comprehensive Logging**: Detailed authentication logging and debugging

## Quick Start

### Basic Usage

```bash
# Check authentication status
awstools auth status

# Detect current authentication method
awstools auth detect

# Login with auto-detection
awstools auth login my-profile

# SSO login
awstools auth sso-login my-sso-profile

# List available profiles
awstools auth list-profiles

# List authentication handlers
awstools auth list-handlers

# Test authentication
awstools auth test s3
```

### Advanced Usage

```bash
# Use specific authentication mode
awstools auth login my-profile --mode sso

# Custom session settings
awstools auth assume my-role --session-name custom-session --duration 7200

# Profile management
awstools auth profile-info my-profile
awstools auth set-profile production

# Environment management
awstools auth show-env
awstools auth clear
```

## Architecture

### Directory Structure

```
services/auth/
├── manifest.sh              # Service metadata and supported methods
├── lib.sh                   # Core authentication library
├── api.sh                   # AWS API wrappers and authentication logic
├── ui.sh                    # User interface and command processing
├── registry.sh              # Plugin registry and handler management
├── config/                  # Configuration files
│   ├── auth.conf            # Global authentication settings
│   ├── sso.conf             # SSO-specific configuration
│   └── custom-external.conf # Custom authentication settings
├── handlers/                # Authentication handler plugins
│   ├── sso.sh               # SSO authentication handler
│   └── example-custom.sh    # Example custom handler
├── hooks/                   # Authentication hooks
│   └── logging.sh           # Authentication logging hooks
└── README.md                # This file
```

### Component Responsibilities

| Component | Purpose | Extensibility |
|-----------|---------|---------------|
| **manifest.sh** | Service metadata and version info | Add new supported methods |
| **lib.sh** | Core utilities and validation | Add new utility functions |
| **api.sh** | AWS CLI wrappers and API calls | Extend existing methods |
| **ui.sh** | Command interface and user interaction | Add new commands |
| **registry.sh** | Plugin management and discovery | Register new handlers |
| **config/** | Configuration management | Add new config files |
| **handlers/** | Authentication implementations | Add new auth methods |
| **hooks/** | Pre/post processing | Add custom processing |

## Available Commands

### Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `status` | Show current authentication status | `awstools auth status` |
| `detect` | Detect authentication method | `awstools auth detect` |
| `login <profile>` | Login using profile (auto-detect) | `awstools auth login dev` |
| `sso-login <profile>` | AWS SSO login | `awstools auth sso-login dev` |
| `assume <profile>` | Assume role using profile | `awstools auth assume my-role` |
| `set-profile <profile>` | Set active profile | `awstools auth set-profile prod` |

### Management Commands

| Command | Description | Example |
|---------|-------------|---------|
| `list-profiles` | List available AWS profiles | `awstools auth list-profiles` |
| `list-handlers` | List authentication handlers | `awstools auth list-handlers` |
| `profile-info <profile>` | Show profile configuration | `awstools auth profile-info dev` |
| `show-env` | Show authentication environment | `awstools auth show-env` |
| `clear` | Clear authentication environment | `awstools auth clear` |
| `test [service]` | Test authentication | `awstools auth test s3` |

## Configuration

### Global Configuration (`config/auth.conf`)

```bash
# Authentication timeout and retry settings
AUTH_TIMEOUT=300
AUTH_RETRY_COUNT=3
AUTH_RETRY_DELAY=2

# Enable authentication caching
AUTH_CACHE_ENABLED=true
AUTH_CACHE_DURATION=3600

# Default authentication method
AUTH_DEFAULT_METHOD="accesskey"

# Security settings
AUTH_SECURE_MODE=true
AUTH_REQUIRE_MFA=false

# Logging settings
AUTH_DEBUG_MODE=false
AUTH_LOG_ATTEMPTS=true
AUTH_LOG_FILE="${HOME}/.aws-utilities/logs/auth.log"
```

### SSO Configuration (`config/sso.conf`)

```bash
# SSO session settings
SSO_DEFAULT_SESSION_NAME="aws-utilities-sso"
SSO_LOGIN_TIMEOUT=300
SSO_AUTO_REFRESH=true

# Browser settings
SSO_BROWSER="auto"
SSO_BROWSER_TIMEOUT=120

# Security settings
SSO_REQUIRE_DEVICE_VERIFICATION=false
SSO_ENCRYPT_TOKENS=false
```

## Extending the Authentication Service

### Creating Custom Authentication Handlers

1. **Create Handler File** (`handlers/my-auth.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

# Handler implementation
handle_my_auth() {
  local param1="${1:-}"
  local param2="${2:-}"
  
  # Your authentication logic here
  log_info "Performing custom authentication"
  
  # Set AWS credentials
  export AWS_ACCESS_KEY_ID="your-access-key"
  export AWS_SECRET_ACCESS_KEY="your-secret-key"
  
  # Validate authentication
  if validate_auth true; then
    log_info "Custom authentication successful"
    return 0
  else
    log_error "Custom authentication failed"
    return 1
  fi
}

# Export functions
export -f handle_my_auth
```

2. **Create Configuration File** (`config/my-auth.conf`):

```bash
# Custom Authentication Configuration
MY_AUTH_API_ENDPOINT="https://auth.example.com"
MY_AUTH_TIMEOUT=30
MY_AUTH_DEBUG_MODE=false
```

3. **Test the Handler**:

```bash
awstools auth list-handlers  # Should show your new handler
```

### Creating Custom Hooks

1. **Create Hook File** (`hooks/my-hook.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Pre-authentication hook
my_pre_auth_hook() {
  local handler_name="$1"
  shift
  local handler_args=("$@")
  
  log_info "Pre-auth hook: $handler_name"
  # Your pre-processing logic here
}

# Post-authentication success hook
my_post_auth_success_hook() {
  local handler_name="$1"
  shift
  local handler_args=("$@")
  
  log_info "Post-auth success hook: $handler_name"
  # Your post-processing logic here
}

# Register hooks (if registry is available)
if command -v register_auth_hook >/dev/null 2>&1; then
  register_auth_hook "pre-auth" "my_pre_auth_hook" 50
  register_auth_hook "post-auth-success" "my_post_auth_success_hook" 50
fi

# Export functions
export -f my_pre_auth_hook
export -f my_post_auth_success_hook
```

## Authentication Methods

### 1. AWS SSO (IAM Identity Center)

```bash
# Configure SSO profile
aws configure sso --profile my-sso

# Login with SSO
awstools auth sso-login my-sso

# Check SSO status
awstools auth status
```

**Configuration**: Uses `config/sso.conf` for SSO-specific settings.

### 2. Access Keys

```bash
# Configure access keys
aws configure --profile my-keys

# Set profile
awstools auth set-profile my-keys

# Verify
awstools auth test
```

### 3. Role Assumption

```bash
# Configure assume role profile
aws configure set role_arn arn:aws:iam::123456789012:role/MyRole --profile my-role
aws configure set source_profile my-source --profile my-role

# Assume role
awstools auth assume my-role

# With MFA
awstools auth assume my-role-with-mfa
```

### 4. Instance Profile

Automatically detected when running on EC2 instances with IAM roles.

```bash
# Check if instance profile is available
awstools auth detect

# Should show: instance-profile
```

### 5. Web Identity

For EKS, Lambda, and other services using web identity tokens.

```bash
# Automatically detected when AWS_WEB_IDENTITY_TOKEN_FILE is set
awstools auth detect
```

### 6. Environment Variables

```bash
# Set environment variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"

# Detect method
awstools auth detect
# Should show: env-vars
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `AWS CLI not found` | Install AWS CLI v2+ |
| `Profile not found` | Check `aws configure list-profiles` |
| `SSO session expired` | Run `awstools auth sso-login <profile>` |
| `Permission denied` | Check IAM permissions |
| `MFA required` | Provide MFA token when prompted |

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Enable debug mode
export DEBUG_AWSTOOLS=true

# Or edit config/auth.conf
AUTH_DEBUG_MODE=true

# Run commands with debug output
awstools auth --debug status
```

### Log Files

Authentication activities are logged to:

- **Console**: Standard output with log levels
- **File**: `${HOME}/.aws-utilities/logs/auth.log` (if configured)

## Security Considerations

### Best Practices

1. **Use SSO**: Prefer AWS SSO over long-term access keys
2. **Short Sessions**: Use shorter session durations for sensitive operations
3. **MFA**: Enable MFA for critical profiles
4. **Least Privilege**: Grant minimal required permissions
5. **Rotate Credentials**: Regularly rotate access keys

### Security Features

- **Secure Storage**: Credentials stored using AWS CLI's secure methods
- **Session Validation**: Automatic credential validation
- **Audit Logging**: Comprehensive authentication logging
- **Environment Isolation**: Clean credential environment management

## Integration

### With Other Services

The authentication service integrates seamlessly with other AWS utilities services:

```bash
# Use authenticated session with other services
awstools auth login my-profile
awstools ec2 list                    # Uses authenticated session
awstools quicksight backup           # Uses authenticated session
```

### External Systems

Custom handlers can integrate with external authentication systems:

- LDAP/Active Directory
- OAuth2/OIDC providers
- Corporate SSO systems
- Custom authentication APIs

## API Reference

### Core Functions

#### `validate_auth([quiet])`
Validates current AWS authentication.

#### `detect_auth_method()`
Detects the current authentication method.

#### `get_account_id()`
Returns the current AWS account ID.

#### `get_region()`
Returns the current AWS region.

#### `profile_exists(profile_name)`
Checks if an AWS profile exists.

#### `is_sso_profile(profile_name)`
Checks if a profile is SSO-configured.

### Handler Functions

#### `execute_auth_handler(handler_name, ...args)`
Executes an authentication handler with hooks.

#### `register_auth_handler(name, function, description, version, dependencies)`
Registers a new authentication handler.

### Hook Functions

#### `register_auth_hook(hook_type, function, priority)`
Registers an authentication hook.

#### `execute_auth_hooks(hook_type, ...args)`
Executes hooks for a specific type.

## Contributing

### Adding New Features

1. **Handlers**: Add new authentication methods in `handlers/`
2. **Hooks**: Add processing hooks in `hooks/`
3. **Configuration**: Add settings in `config/`
4. **Commands**: Extend `ui.sh` for new commands
5. **Documentation**: Update this README

### Testing

```bash
# Test basic functionality
awstools auth help
awstools auth list-handlers
awstools auth status

# Test with different profiles
awstools auth login test-profile
awstools auth test

# Test error handling
awstools auth login non-existent-profile
```

## Version History

- **v2.0.0**: Plugin architecture with handlers and hooks
- **v1.0.0**: Basic authentication with SSO, access keys, and role assumption

## License

This project follows the same license as the parent AWS Utilities project.

## Support

For issues and questions:

1. Check this documentation
2. Enable debug mode for troubleshooting
3. Check log files for detailed error information
4. Review AWS CLI configuration: `aws configure list`

---

**Note**: This authentication service requires AWS CLI v2+ and appropriate AWS credentials/permissions.
