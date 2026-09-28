#!/usr/bin/env bash

set -euo pipefail

echo "Installing ABX dependencies..."

sudo apt-get update

sudo apt-get install -y \
    clang \
    lldb \
    gdb \
    pkg-config \
    libsdl2-dev \
    libsdl2-image-dev \
    libsdl2-ttf-dev

echo "Installing Odin..."

ODIN_VERSION="dev-2026-09"
ODIN_URL="https://github.com/odin-lang/Odin/releases/download/${ODIN_VERSION}/odin-linux-amd64-${ODIN_VERSION}.tar.gz"

sudo mkdir -p /opt/odin

curl -L "$ODIN_URL" -o /tmp/odin.tar.gz

sudo tar -xzf /tmp/odin.tar.gz -C /opt/odin

ODIN_BIN="$(find /opt/odin -type f -name odin -perm -111 | head -n 1)"

if [ -z "$ODIN_BIN" ]; then
    echo "Could not find Odin compiler"
    exit 1
fi

sudo ln -sf "$ODIN_BIN" /usr/local/bin/odin

echo
echo "Odin:"
odin version

echo
echo "Checking ABX..."

odin check src

echo
echo "ABX Codespace ready!"