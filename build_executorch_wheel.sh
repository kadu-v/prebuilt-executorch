#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

(
    export CMAKE_ARGS="-DEXECUTORCH_BUILD_PYBIND=ON -DEXECUTORCH_BUILD_COREML=ON -DEXECUTORCH_BUILD_MPS=ON -DEXECUTORCH_BUILD_XNNPACK=ON"
    export CMAKE_BUILD_ARGS=""
    cd executorch
    python3 setup.py bdist_wheel \
        --dist-dir=$SCRIPT_DIR/out-executorch-wheel
)

