#!/bin/bash
# Control Panel installation wrapper

# Check if we should use the simple version (default for now)
USE_SIMPLE="${USE_SIMPLE:-true}"

if [[ "$USE_SIMPLE" == "true" ]]; then
    # Use the simple static control panel
    source "${SCRIPT_DIR}/components/control-panel/install-simple.sh"
else
    # Use the full control panel (when images are available)
    source "${SCRIPT_DIR}/components/control-panel/install-full.sh"
fi