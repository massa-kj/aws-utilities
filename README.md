# AWS Utilities

Scripts and cheat sheets for AWS work.
A unified command-line interface for managing multiple AWS services with a clean, modular architecture.

## Features

- **Unified CLI**: Single entry point (`awstools.sh`) for all AWS operations
- **Modular Architecture**: Clean separation between services and layers
- **Dynamic Service Discovery**: Automatic detection of available services
- **Global Commands**: Cross-service utilities like authentication detection
- **Flexible Configuration**: Profile and region override support
- **Comprehensive Logging**: Debug-friendly logging with color support
- **Extensible Design**: Easy to add new services and commands

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/massa-kj/aws-utilities.git
   cd aws-utilities
   ```

2. Make the main script executable:
   ```bash
   chmod +x awstools.sh
   ```

3. Ensure AWS CLI v2+ is installed and configured:
   ```bash
   aws --version
   aws configure list
   ```

## Quick Start

### Basic Usage
```bash
# Show help and available services
./awstools.sh --help

# Detect current authentication method
./awstools.sh detect-auth

# List EC2 instances
./awstools.sh ec2 list

# Get help for a specific service
./awstools.sh ec2 help
```

### Common Operations
```bash
# EC2 Management
./awstools.sh ec2 list
./awstools.sh ec2 start i-1234567890abcdef0
./awstools.sh ec2 stop i-1234567890abcdef0
./awstools.sh ec2 describe i-1234567890abcdef0

# QuickSight Management
./awstools.sh quicksight list
./awstools.sh quicksight backup --analysis-id abc123

# Profile and Region Override
./awstools.sh ec2 list --profile production --region us-west-2
```

## Architecture

### Project Structure
```
aws-utilities/
├── awstools.sh              # Main entry point
├── config.sh                # Global configuration
├── .env.local               # Optional local config
├── commands/                 # Global commands
│   ├── manifest.sh           # Command registry
│   └── detect-auth.sh        # Authentication detection
├── common/                   # Shared utilities
│   ├── logger.sh             # Logging system
│   └── utils.sh              # Common functions
└── services/                 # Service implementations
    ├── {command}/            # Individual service (e.g., ec2, quicksight)
    │   ├── manifest.sh       # Service metadata
    │   ├── lib.sh            # Service utilities
    │   ├── api.sh            # AWS API wrappers
    │   └── ui.sh             # Command interface
    └── .../
```

### Layer Architecture
Each service follows a 3-layer architecture:

| Layer | File | Responsibility |
|-------|------|----------------|
| **UI Layer** | `ui.sh` | Command parsing, user interaction, workflow control |
| **API Layer** | `api.sh` | AWS CLI wrappers, API calls, response processing |
| **Lib Layer** | `lib.sh` | Service-specific utilities, validation, and configuration management |

## Available Services

### EC2 Service
Manage EC2 instances with enhanced state checking and validation.

```bash
./awstools.sh ec2 list                    # List all instances
./awstools.sh ec2 start <instance-id>     # Start instance with state validation
./awstools.sh ec2 stop <instance-id>      # Stop instance with confirmation
./awstools.sh ec2 describe <instance-id>  # Show detailed instance info
```

### QuickSight Service
Manage QuickSight resources including analyses and datasets.

```bash
./awstools.sh quicksight list             # List resources
./awstools.sh quicksight backup           # Backup operations
```

## Global Commands

### Authentication Detection
```bash
./awstools.sh detect-auth
# Output examples:
# profile:my-profile    # Using AWS CLI profile
# env-vars              # Using environment variables
# iam-role              # Using IAM role (EC2, Lambda, etc.)
```

## Configuration

### Environment Variables
```bash
# AWS Configuration
export AWS_PROFILE=my-profile
export AWS_REGION=us-east-1

# Logging Configuration
export LOG_LEVEL=debug          # debug, info, warn, error
export LOG_FILE=./aws-tools.log # Optional file output
export LOG_COLOR=false          # Disable colors
```

### Local Configuration
Create `.env.local` in the project root for user-specific settings:
```bash
# .env.local
AWS_PROFILE=my-default-profile
AWS_REGION=ap-northeast-1
DEBUG_AWSTOOLS=true
```

## Development

### Adding a New Service

1. **Create service directory**:
   ```bash
   mkdir -p services/myservice
   ```

2. **Create manifest.sh**:
   ```bash
   # services/myservice/manifest.sh
   SERVICE_NAME="myservice"
   SERVICE_DESC="Manage MyService resources"
   SERVICE_VERSION="1.0.0"
   ```

3. **Implement layers**:
   - `lib.sh`: Configuration and utilities
   - `api.sh`: AWS API wrappers
   - `ui.sh`: Command interface

4. **Test the service**:
   ```bash
   ./awstools.sh myservice help
   ```

### Adding a Global Command

1. **Add to manifest**:
   ```bash
   # commands/manifest.sh
   ["my-command"]="Description of my command"
   ```

2. **Create command script**:
   ```bash
   # commands/my-command.sh
   #!/usr/bin/env bash
   # Implementation here
   ```

3. **Make executable**:
   ```bash
   chmod +x commands/my-command.sh
   ```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Related

- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)
- [AWS Service Documentation](https://docs.aws.amazon.com/)

---

**Note**: This tool is designed for AWS operations and requires appropriate AWS credentials and permissions.
