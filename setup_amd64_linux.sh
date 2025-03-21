#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install dependencies
# $SCRIPT_DIR/executorch/install_requirements.sh
$SCRIPT_DIR/executorch/install_executorch.sh --pybind xnnpack