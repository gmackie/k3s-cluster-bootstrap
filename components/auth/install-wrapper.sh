#!/bin/bash
# Wrapper for auth component to work with bootstrap system

# The auth install script expects to be called with "install" parameter
# and needs proper environment setup

# Ensure we're using the right SCRIPT_DIR for the auth component
export ORIGINAL_SCRIPT_DIR="${SCRIPT_DIR}"
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call the actual install script
bash "${SCRIPT_DIR}/install.sh" install

# Restore SCRIPT_DIR
export SCRIPT_DIR="${ORIGINAL_SCRIPT_DIR}"