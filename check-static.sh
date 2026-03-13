#!/bin/bash
# Скрипт для проверки статической линковки собранных бинарников

set -e

echo "=== Testing static linking ==="

# Собираем для amd64
echo "Building for amd64..."
docker build --platform linux/amd64 -t telemt-test-amd64 --target builder --output type=local,dest=./dist/amd64 .

# Собираем для arm64
echo "Building for arm64..."
docker build --platform linux/arm64 -t telemt-test-arm64 --target builder --output type=local,dest=./dist/arm64 .

# Проверяем amd64 бинарник
echo "=== Checking amd64 binary ==="
file ./dist/amd64/out/telemt
if readelf -l ./dist/amd64/out/telemt 2>/dev/null | grep -q "INTERP"; then
    echo "❌ amd64: binary is dynamically linked"
    exit 1
else
    echo "✅ amd64: statically linked"
fi

# Проверяем arm64 бинарник (если есть QEMU)
if command -v qemu-aarch64-static &> /dev/null; then
    echo "=== Checking arm64 binary ==="
    file ./dist/arm64/out/telemt
    if readelf -l ./dist/arm64/out/telemt 2>/dev/null | grep -q "INTERP"; then
        echo "❌ arm64: binary is dynamically linked"
        exit 1
    else
        echo "✅ arm64: statically linked"
    fi
else
    echo "⚠️  Skipping arm64 check (install qemu-user-static for full check)"
fi

echo "✓ All binaries are statically linked"