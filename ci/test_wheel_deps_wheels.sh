#!/bin/bash
# Copyright (c) 2023-2024, NVIDIA CORPORATION

set -euo pipefail

# cuRAND versions don't follow the toolkit versions - map toolkit versions to
# appropriate cuRAND versions
declare -A CTK_CURAND_VMAP=( ["12.8"]="10.3.9" ["12.9"]="10.3.10")
CUDA_VER_MAJOR_MINOR=${CUDA_VER%.*}
CURAND_VER="${CTK_CURAND_VMAP[${CUDA_VER_MAJOR_MINOR}]}"

rapids-logger "Install testing dependencies"
# TODO: Replace with rapids-dependency-file-generator
python -m pip install \
    psutil \
    cffi \
    "cuda-python==${CUDA_VER_MAJOR_MINOR}.*" \
    "nvidia-cuda-runtime-cu12==${CUDA_VER_MAJOR_MINOR}.*" \
    "nvidia-curand-cu12==${CURAND_VER}.*" \
    "nvidia-cuda-nvcc-cu12==${CUDA_VER_MAJOR_MINOR}.*" \
    "nvidia-cuda-nvrtc-cu12==${CUDA_VER_MAJOR_MINOR}.*" \
    pynvjitlink-cu12 \
    pytest


rapids-logger "Install wheel"
package=$(realpath wheel/numba_cuda*.whl)
echo "Package path: $package"
python -m pip install $package


rapids-logger "Build tests"
PY_SCRIPT="
import numba_cuda
root = numba_cuda.__file__.rstrip('__init__.py')
test_dir = root + \"numba/cuda/tests/test_binary_generation/\"
print(test_dir)
"
NUMBA_CUDA_TEST_BIN_DIR=$(python -c "$PY_SCRIPT")
pushd $NUMBA_CUDA_TEST_BIN_DIR
make
popd


rapids-logger "Check GPU usage"
nvidia-smi

RAPIDS_TESTS_DIR=${RAPIDS_TESTS_DIR:-"${PWD}/test-results"}/
mkdir -p "${RAPIDS_TESTS_DIR}"
pushd "${RAPIDS_TESTS_DIR}"

rapids-logger "Show Numba system info"
python -m numba --sysinfo

# remove cuda-nvvm-12-5 leaving libnvvm.so from nvidia-cuda-nvcc-cu12 only
apt-get update
apt remove --purge `dpkg --get-selections | grep cuda-nvvm | awk '{print $1}'` -y
apt remove --purge `dpkg --get-selections | grep cuda-nvrtc | awk '{print $1}'` -y

rapids-logger "Run Tests"
NUMBA_CUDA_ENABLE_PYNVJITLINK=1 NUMBA_CUDA_TEST_BIN_DIR=$NUMBA_CUDA_TEST_BIN_DIR python -m numba.runtests numba.cuda.tests -v

popd
