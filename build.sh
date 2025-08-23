#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXECUTORCH_DIR=$SCRIPT_DIR/executorch
BUILD_DIR=$EXECUTORCH_DIR/cmake-out
BUILD_MODE=Release
NO_VENV=0
DEVTOOLS=OFF

###############################################################################
# Auxiliary functions                                                         #
###############################################################################
function usage() {
    echo "Usage: $0 --target=<target> [--clean] [--mode=<mode>]"
    echo "--target: target architecture (e.g., aarch64-unknown-linux-gnu, apple-*)"
    echo "--clean: clean the build directory"
    echo "--mode: build mode (e.g., Release, Debug)"
    echo "--no-venv: do not use pyenv"
    echo "--devtools: build devtools"
}

function println() {
    echo "###############################################################################"
    echo "$1"
    echo "###############################################################################"
}

function build_for_apple() {
    local buck2=$1
    local flatc=$2
    local platform=$3
    local platform_target=$4
    local target_triple=$5
    local install_dir=$6

    local TOOLCHAIN="${EXECUTORCH_DIR}/third-party/ios-cmake/ios.toolchain.cmake"

    println "Building for ${target_triple}"
    mkdir -p $BUILD_DIR && cd $BUILD_DIR || exit 1
    cmake $EXECUTORCH_DIR -G Xcode \
        -DCMAKE_BUILD_TYPE="$BUILD_MODE" \
        -DCMAKE_PREFIX_PATH="$(python -c 'import torch as _; print(_.__path__[0])')" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
        -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
        -DBUCK2="$buck2" \
        -DPYTHON_EXECUTABLE="python" \
        -DFLATC_EXECUTABLE="$flatc" \
        -DEXECUTORCH_BUILD_COREML=ON \
        -DEXECUTORCH_BUILD_MPS=ON \
        -DEXECUTORCH_BUILD_XNNPACK=ON \
        -DEXECUTORCH_XNNPACK_ENABLE_KLEIDI=ON \
        -DEXECUTORCH_XNNPACK_SHARED_WORKSPACE=ON \
        -DEXECUTORCH_BUILD_EXTENSION_APPLE=ON \
        -DEXECUTORCH_BUILD_EXTENSION_DATA_LOADER=ON \
        -DEXECUTORCH_BUILD_EXTENSION_MODULE=ON \
        -DEXECUTORCH_BUILD_EXTENSION_FLAT_TENSOR=ON \
        -DEXECUTORCH_BUILD_EXTENSION_TENSOR=ON \
        -DEXECUTORCH_BUILD_KERNELS_CUSTOM=ON \
        -DEXECUTORCH_BUILD_KERNELS_OPTIMIZED=ON \
        -DEXECUTORCH_BUILD_KERNELS_QUANTIZED=ON \
        -DEXECUTORCH_BUILD_DEVTOOLS=$DEVTOOLS \
        -DEXECUTORCH_ENABLE_EVENT_TRACER=$DEVTOOLS \
        -Dprotobuf_BUILD_TESTS=OFF \
        -Dprotobuf_BUILD_EXAMPLES=OFF \
        -DCMAKE_ARCHIVE_OUTPUT_DIRECTORY="$BUILD_DIR" \
        -DPLATFORM=$platform \
        -DDEPLOYMENT_TARGET=$platform_target

    cmake --build . \
        -j4 \
        --config $BUILD_MODE \
        --verbose
    
    # build devtools
    if [[ $DEVTOOLS == "ON" ]]; then
        cmake --build . \
            -j4 \
            --config $BUILD_MODE \
            --target coremldelegate
        cmake --build . \
            -j4 \
            --config $BUILD_MODE \
            --target etdump \
            --target flatccrt
    fi
 
    println "Install all libraries to the ${install_dir} directory"
    lower_mode=$(echo $BUILD_MODE | tr '[:upper:]' '[:lower:]')
    mkdir -p $install_dir
    cmake --install . \
        --config $BUILD_MODE \
        --prefix $install_dir
    
    if [[ $DEVTOOLS == "ON" ]]; then
        println "Copy devtools libraries to the target/executorch-prebuilt directory"
        cp $BUILD_DIR/lib/*.a $install_dir/lib
        # rename libfaltccrt_d.a to libfaltccrt.a
        if [[ -f $install_dir/lib/libflatccrt_d.a ]]; then
            mv $install_dir/lib/libflatccrt_d.a $install_dir/lib/libflatccrt.a
        fi
    fi
}

function extract_all_headers() {
    cd $EXECUTORCH_DIR
    mkdir -p $EXECUTORCH_DIR/../target/executorch-prebuilt/include/executorch
    find . -name "*.h" -exec cp --parents {} $EXECUTORCH_DIR/../target/executorch-prebuilt/include/executorch \;
}
###############################################################################
# Parse command line arguments                                                #
###############################################################################
for arg in "$@"; do
    case $arg in
        --target=*) TARGET_TRIPLE="${arg#*=}";;
        --clean) CLEAN=1;;
        --mode=*) BUILD_MODE="${arg#*=}";;
        --no-venv) NO_VENV=1;;
        --devtools) DEVTOOLS=ON;;
        *)
        echo "Invalid argument: $arg"
        exit 1
        ;;
    esac
done


###############################################################################
# Main                                                                        #
###############################################################################

if [[ -z "$TARGET_TRIPLE" ]] && [[ -z "$CLEAN" ]]; then
    usage
    exit 1
fi

# Check the MacOS environment
if [[ $(uname) == "Darwin" ]]; then
    println "Checking python environment is activated"
    if [[ -z "$VIRTUAL_ENV" ]] && [[ $NO_VENV -eq 0 ]]; then
        echo "Please activate a python environment"
        exit 1
    fi

    println "Checking buck2 version"
    BUCK2_VERSION=$(cat ${SCRIPT_DIR}/executorch/.ci/docker/ci_commit_pins/buck2.txt)
    BUCK2_EXECUTABLE="${SCRIPT_DIR}/executorch/buck-out/buck2-aarch64-apple-darwin"
    if [[ ! -f "${BUCK2_EXECUTABLE}" ]]; then
        wget "https://github.com/facebook/buck2/releases/download/${BUCK2_VERSION}/buck2-aarch64-apple-darwin.zst"
        unzstd buck2-aarch64-apple-darwin.zst
        chmod u+x buck2-aarch64-apple-darwin
        mv buck2-aarch64-apple-darwin $BUCK2_EXECUTABLE
        rm buck2-aarch64-apple-darwin.zst
    else
        echo "Buck2 already downloaded"
    fi
fi

if [[ $TARGET_TRIPLE == "aarch64-unknown-linux-gnu" ]] || [[ $TARGET_TRIPLE == "x86_64-unknown-linux-gnu" ]]; then
    println "Building for aarch64-unknown-linux-gnu"

    # Check the host machine architecture
    if [[ $(uname -m) != "aarch64" ]] && [[ $(uname -m) != "x86_64" ]]; then
        println "Host machine architecture is not aarch64 and x86_64"
        exit 1
    fi
    # Check the host machin os type
    if [[ $(uname) != "Linux" ]]; then
        println "Host machine OS is not Linux"
        exit 1
    fi

    # Build the project
    (
        cd $EXECUTORCH_DIR
        cmake . -B $BUILD_DIR \
            -DEXECUTORCH_BUILD_EXTENSION_MODULE=ON \
            -DEXECUTORCH_BUILD_EXTENSION_FLAT_TENSOR=ON \
            -DEXECUTORCH_BUILD_EXTENSION_TENSOR=ON \
            -DEXECUTORCH_BUILD_EXTENSION_DATA_LOADER=ON \
            -DEXECUTORCH_BUILD_EXTENSION_RUNNER_UTIL=ON \
            -DEXECUTORCH_BUILD_EXECUTOR_RUNNER=OFF \
            -DCMAKE_BUILD_TYPE=$BUILD_MODE 
        cd $BUILD_DIR
        make -j$(nproc)

        println "Install all libraries to the target/executorch-prebuilt directory"
        lower_mode=$(echo $BUILD_MODE | tr '[:upper:]' '[:lower:]')
        mkdir -p $EXECUTORCH_DIR/../target/executorch-prebuilt/$TARGET_TRIPLE/$lower_mode
        cmake --install . --prefix $EXECUTORCH_DIR/../target/executorch-prebuilt/$TARGET_TRIPLE/$lower_mode

        println "Extract all headers from executorch and copy them to the include directory"
        extract_all_headers
    )
elif [[ $TARGET_TRIPLE == "aarch64-linux-android" ]]; then
    println "Building for ${TARGET_TRIPLE}"
    
    if [[ -z $ANDROID_NDK_HOME ]]; then
        println "Please set the ANDROID_NDK_HOME environment variable"
        exit 1
    fi
    LOWER_MODE=$(echo $BUILD_MODE | tr '[:upper:]' '[:lower:]')
    INSTALL_DIR=$EXECUTORCH_DIR/../target/executorch-prebuilt/$TARGET_TRIPLE/$LOWER_MODE
    if [[ $DEVTOOLS == "ON" ]]; then
        INSTALL_DIR=$EXECUTORCH_DIR/../target/executorch-prebuilt/$TARGET_TRIPLE/devtools
    fi
    cd $EXECUTORCH_DIR
    cmake . -B $BUILD_DIR \
        -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
        -DANDROID_ABI=arm64-v8a \
        -DEXECUTORCH_BUILD_VULKAN=ON \
        -DEXECUTORCH_BUILD_XNNPACK=ON \
        -DEXECUTORCH_XNNPACK_ENABLE_KLEIDI=ON \
        -DEXECUTORCH_XNNPACK_SHARED_WORKSPACE=ON \
        -DEXECUTORCH_BUILD_EXTENSION_DATA_LOADER=ON \
        -DEXECUTORCH_BUILD_EXTENSION_MODULE=ON \
        -DEXECUTORCH_BUILD_EXTENSION_FLAT_TENSOR=ON \
        -DEXECUTORCH_BUILD_EXTENSION_TENSOR=ON \
        -DEXECUTORCH_BUILD_KERNELS_CUSTOM=ON \
        -DEXECUTORCH_BUILD_KERNELS_OPTIMIZED=ON \
        -DEXECUTORCH_BUILD_KERNELS_QUANTIZED=ON \
        -DEXECUTORCH_BUILD_DEVTOOLS=$DEVTOOLS \
        -DEXECUTORCH_ENABLE_EVENT_TRACER=$DEVTOOLS \
        -Dprotobuf_BUILD_TESTS=OFF \
        -Dprotobuf_BUILD_EXAMPLES=OFF \
        -DPYTHON_EXECUTABLE=python \
        -DCMAKE_BUILD_TYPE=$BUILD_MODE
    cmake --build $BUILD_DIR -j$(nproc)

    mkdir -p $INSTALL_DIR
    println "Install all libraries to the ${INSTALL_DIR} directory"
    cmake --install $BUILD_DIR --prefix $INSTALL_DIR

    if [[ $DEVTOOLS == "ON" ]]; then
        println "Copy devtools libraries to the target/executorch-prebuilt directory"
        cp $BUILD_DIR/lib/*.a $INSTALL_DIR/lib
        # rename libfaltccrt_d.a to libfaltccrt.a
        if [[ -f $INSTALL_DIR/lib/libflatccrt_d.a ]]; then
            mv $INSTALL_DIR/lib/libflatccrt_d.a \
                $INSTALL_DIR/lib/libflatccrt.a
        fi
    fi

    println "Extract all headers from executorch and copy them to the include directory"
    extract_all_headers
elif [[ $TARGET_TRIPLE == "aarch64-apple-ios" ]]; then
    PLATFORMS=(
        "MAC_ARM64"
        "OS64"
        "SIMULATORARM64"
    )
    PLATFORM_TARGETS=(
        "10.15"
        "17.0"
        "17.0"
    )
    TARGET_TRIPLES=(
        "aarch64-apple-darwin"
        "aarch64-apple-ios"
        "aarch64-apple-ios-sim"
    )

    if [[ $DEVTOOLS == "ON" ]]; then
        PLATFORMS=(
            "MAC_ARM64"
        )
        PLATFORM_TARGETS=(
            "10.15"
        )
        TARGET_TRIPLES=(
            "aarch64-apple-darwin"
        )
    fi

    # Check the flatc executable is installed
    FLATC=$(which flatc)
    if [[ -z $FLATC ]]; then
        println "Install flatc"
        ${EXECUTORCH_DIR}/build/install_flatc.sh
        FLATC="${EXECUTORCH_DIR}/third-party/flatbuffers/cmake-out/flatc"
    fi

    for index in ${!PLATFORMS[*]}; do
        rm -rf $BUILD_DIR
        cd $EXECUTORCH_DIR
        LOWER_MODE=$(echo $BUILD_MODE | tr '[:upper:]' '[:lower:]')
        INSTALL_DIR=$EXECUTORCH_DIR/../target/executorch-prebuilt/${TARGET_TRIPLES[$index]}/$LOWER_MODE
        if [[ $DEVTOOLS == "ON" ]]; then
            INSTALL_DIR=$EXECUTORCH_DIR/../target/executorch-prebuilt/${TARGET_TRIPLES[$index]}/devtools
        fi
        build_for_apple \
            "${BUCK2_EXECUTABLE}" \
            "${FLATC}" \
            "${PLATFORMS[$index]}" \
            "${PLATFORM_TARGETS[$index]}" \
            "${TARGET_TRIPLES[$index]}" \
            "${INSTALL_DIR}"
    done

    println "Extract all headers from executorch and copy them to the include directory"
    extract_all_headers
elif [[ ! -z $TARGET_TRIPLE ]]; then
    println "Unsupported target architecture: $TARGET_TRIPLE"
    exit 1
fi

if [[ ! -z $CLEAN ]]; then
    println "Cleaning the build directory: $BUILD_DIR"
    rm -rf $BUILD_DIR
fi

