#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install dependencies
$SCRIPT_DIR/executorch/install_requirements.sh --use-pt-pinned-commit
$SCRIPT_DIR/executorch/install_executorch.sh --pybind coreml mps xnnpack 
$SCRIPT_DIR/executorch/backends/apple/coreml/scripts/install_requirements.sh
$SCRIPT_DIR/executorch/backends/apple/mps/install_requirements.sh