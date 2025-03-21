#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Rewrite $SCRIPT_DIR/executorch/install_requirements.sh due to executorch bug
# Replace torch==2.7.0.{NIGHTLY_VERSION} to torch==2.7.0.dev20250310
sed -i '' 's/torch==2.7.0\.[0-9]*/torch==2.7.0.dev20250310/g' $SCRIPT_DIR/executorch/install_requirements.sh

# Install dependencies
$SCRIPT_DIR/executorch/install_requirements.sh
$SCRIPT_DIR/executorch/install_executorch.sh --pybind xnnpack
