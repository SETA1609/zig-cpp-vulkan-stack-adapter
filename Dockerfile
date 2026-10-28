# Reproducible dev/test container for the vulkan-stack adapter.
#
#   docker build -t vk-stack .                         # build the image
#   docker run --rm vk-stack                           # default: fmt + build + smoke + contract test
#   docker run --rm vk-stack bash scripts/ci.sh clang-format
#   docker run --rm vk-stack bash scripts/ci.sh shaderc        # build with the system shaderc (-Dshaderc)
#   docker run --rm vk-stack bash scripts/ci.sh device-tests   # volk/VMA against lavapipe (software Vulkan)
#
# Headless by design: lavapipe is the only Vulkan ICD, so device tests need no
# GPU; the test harness opens no window, so no display is needed. Build deps for
# the C++ VMA bridge (vulkan headers) are vendored / fetched by Zig; -Dshaderc
# links the system shaderc (libshaderc-dev, from Ubuntu's universe component). First `zig build` fetches the pinned deps (network).
FROM ubuntu:24.04
ARG ZIG_VERSION=0.17.0
ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu's image enables main only; libshaderc-dev is in universe.
RUN sed -i 's/^Components: .*/Components: main universe/' /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils git python3 python3-pip \
      mesa-vulkan-drivers libvulkan1 vulkan-tools \
      libshaderc-dev \
      clang-format-18 \
    && rm -rf /var/lib/apt/lists/*

# Zig, pinned — URL resolved from the official release index (no guessing the filename).
RUN set -eux; \
    url="$(curl -fsSL https://ziglang.org/download/index.json \
      | python3 -c "import sys,json;print(json.load(sys.stdin)['${ZIG_VERSION}']['x86_64-linux']['tarball'])")"; \
    curl -fsSL "$url" -o /tmp/zig.tar.xz; \
    mkdir -p /opt/zig; tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1; \
    ln -s /opt/zig/zig /usr/local/bin/zig; rm /tmp/zig.tar.xz; zig version

# lavapipe is the sole ICD → device tests run headless, no GPU.
ENV VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
ENV CLANG_FORMAT=clang-format-18

WORKDIR /work
COPY . .
RUN python3 -m pip install --break-system-packages --quiet pyyaml || true

CMD ["bash", "scripts/ci.sh", "check"]
