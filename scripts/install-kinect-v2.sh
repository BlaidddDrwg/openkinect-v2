#!/bin/bash
# Install Xbox One Kinect (v2) drivers on Ubuntu
# This builds libfreenect2 from source since it's not in default repositories

set -e

echo "Installing Xbox One Kinect (v2) drivers..."
echo "========================================"

# CUDA 12.0 (Ubuntu 24.04's nvidia-cuda-toolkit) refuses GCC > 12, so we
# build the CUDA bits with gcc-12. Check for it up front and tell the user
# how to install it rather than pulling it in silently.
if ! command -v gcc-12 >/dev/null 2>&1 || ! command -v g++-12 >/dev/null 2>&1; then
    echo "ERROR: gcc-12 / g++-12 are required as the CUDA host compiler but were not found." >&2
    echo "Install them with:" >&2
    echo "    sudo apt install gcc-12 g++-12" >&2
    exit 1
fi

# Install dependencies
echo "Installing build dependencies..."
sudo apt update
sudo apt install -y \
    cmake \
    pkg-config \
    libusb-1.0-0-dev \
    libturbojpeg0-dev \
    libglfw3-dev \
    build-essential \
    git

# Create temporary build directory
BUILD_DIR=$(mktemp -d)
cd "$BUILD_DIR"

# Clone libfreenect2
echo "Cloning libfreenect2 repository..."
git clone https://github.com/OpenKinect/libfreenect2.git
cd libfreenect2

# Create build directory
mkdir build && cd build

# Configure build
# Notes on the extra flags below:
#   * CUDA 12.0 (the version in nvidia-cuda-toolkit on Ubuntu 24.04) refuses to
#     build with GCC > 12 — the check lives in /usr/include/crt/host_config.h.
#     We point nvcc at /usr/bin/gcc-12 so the system default (gcc-13) is left
#     untouched for everything else.
#   * libfreenect2's CUDA depth packet processor #includes "helper_math.h",
#     which Ubuntu ships under /usr/share/doc/nvidia-cuda-toolkit/examples/
#     Common/ rather than on the default nvcc include path.
CUDA_SAMPLES_COMMON=/usr/share/doc/nvidia-cuda-toolkit/examples/Common
echo "Configuring build..."
#   * OpenCL is disabled because the Khronos OpenCL headers now define
#     CL_ICDL_VERSION as a macro, which collides with a local variable of
#     the same name in libfreenect2's opencl_depth_packet_processor.cpp.
#     CUDA, OpenGL, and CPU depth backends remain available.
cmake .. \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DENABLE_OPENCL=OFF \
    -DCUDA_HOST_COMPILER=/usr/bin/gcc-12 \
    -DCUDA_PROPAGATE_HOST_FLAGS=OFF \
    -DCUDA_NVCC_FLAGS="-I${CUDA_SAMPLES_COMMON}" \
    -DCMAKE_CXX_FLAGS="-I${CUDA_SAMPLES_COMMON}"

# Build with all available cores
echo "Building libfreenect2 (this may take a few minutes)..."
make -j$(nproc)

# Install
echo "Installing libfreenect2..."
sudo make install

# Install Protonect binary. Depending on the libfreenect2 version, it ends up
# in <source>/bin/ or <source>/examples/bin/, so search the whole source tree
# and fail loudly if it isn't there — silent skip used to lie via the final
# "run /usr/local/bin/Protonect" message.
PROTONECT_SRC=$(find .. -type f -name Protonect -executable | head -n 1)
if [ -z "$PROTONECT_SRC" ]; then
    echo "ERROR: Protonect was not built. Leaving build tree at $BUILD_DIR for inspection." >&2
    SKIP_CLEANUP=1
    exit 1
fi
echo "Installing Protonect test program from $PROTONECT_SRC ..."
sudo install -m 0755 "$PROTONECT_SRC" /usr/local/bin/Protonect

# Update library cache
sudo ldconfig

# Install udev rules for device permissions
echo "Installing udev rules..."
sudo cp ../platform/linux/udev/90-kinect2.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger

# Clean up build directory (skipped if an earlier step asked us to leave it
# behind for inspection).
cd /
if [ -z "${SKIP_CLEANUP:-}" ]; then
    rm -rf "$BUILD_DIR"
fi

echo ""
echo "Installation complete!"
echo "====================="
echo ""
echo "You may need to unplug and replug your Kinect for the changes to take effect."
echo ""
echo "To test your Kinect v2, run:"
echo "  /usr/local/bin/Protonect"
echo ""
echo "This will open windows showing RGB camera, depth, and IR feeds."