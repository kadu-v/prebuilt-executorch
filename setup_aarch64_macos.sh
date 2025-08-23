#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


# Install dependencies
(
    cd $SCRIPT_DIR/executorch
    ./install_requirements.sh 
    ./install_executorch.sh --use-pt-pinned-commit 
)