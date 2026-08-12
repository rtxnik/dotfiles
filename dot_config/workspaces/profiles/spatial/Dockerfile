FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# cairosvg renders through libcairo and selects fonts through fontconfig. A
# container without a Cyrillic-capable font drops Cyrillic text SILENTLY — no
# warning, no error, just missing glyphs in the deliverable. DejaVu also serves
# the Pillow overlays that stand in for cv2.putText, whose Hershey fonts have no
# Cyrillic at all.
#
# libglib2.0-0t64 is OpenCV's dependency under noble's t64 ABI transition; the
# pre-noble name libglib2.0-0 does not exist on 24.04. libgl1 is not needed by
# opencv-python-headless, which the project seed pins, but it keeps a manual
# swap to the full opencv-python wheel from failing with ImportError:
# libGL.so.1.
#
# poppler-utils and imagemagick are the raster back-office: page extraction if
# the finishing schedules arrive as PDF, and batch preparation of scans.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl git iproute2 unzip build-essential \
       libcairo2 fontconfig fonts-dejavu-core fonts-noto-core \
       libglib2.0-0t64 libgl1 \
       poppler-utils imagemagick \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://mise.jdx.dev/install.sh | sh

ENV PATH="/home/vscode/.local/bin:${PATH}"
