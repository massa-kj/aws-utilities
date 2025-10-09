#=============================================================
# Auth Service Manifest
#=============================================================
SERVICE_NAME="auth"
SERVICE_DESC="Manage AWS authentication (SSO/profiles/assume-role/credentials)"
SERVICE_VERSION="2.0.0"
SERVICE_DEPENDS="aws-cli>=2.0"

# Supported authentication methods
AUTH_METHODS="auto sso accesskey assume instance-profile web-identity"
