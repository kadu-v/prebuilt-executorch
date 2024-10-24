#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


(
    cd executorch/backends/apple/coreml/runtime/inmemoryfs
    python setup.py bdist_wheel \
    --dist-dir=$SCRIPT_DIR/out-coreml-wheel
)