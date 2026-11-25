#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

injected_count=0

for module in decoder_ffmpeg decoder_mpegh mpvplayer; do
    aar_path="${ROOT}/libraries/${module}/buildout/outputs/aar/lib-${module}-release.aar"
    so_src="${ROOT}/libraries/${module}/src/main/jniLibs"
    aar_name=$(basename "$aar_path")

    # AAR 不存在则跳过
    if [ ! -f "$aar_path" ]; then
        echo "[$module] AAR 不存在，跳过"
        continue
    fi

    # .so 源目录不存在则跳过
    if [ ! -d "$so_src" ]; then
        echo "[$module] .so 源目录不存在，跳过"
        continue
    fi

    # 检查是否已包含 .so
    has_so=$(unzip -l "$aar_path" 2>/dev/null | grep -c "\.so" || true)
    if [ "$has_so" -gt 0 ]; then
        echo "[$module] AAR 已含 ${has_so} 个 .so，跳过"
        continue
    fi

    echo "[$module] 注入 .so -> $aar_name ..."

    tmp=$(mktemp -d)
    cp "$aar_path" "$tmp/temp.aar"
    (cd "$tmp" && unzip -q temp.aar)

    # 复制 so 到 jni/
    for arch_dir in "$so_src"/*/; do
        arch=$(basename "$arch_dir")
        mkdir -p "$tmp/jni/$arch"
        for so_file in "$arch_dir"*.so; do
            [ -f "$so_file" ] && cp "$so_file" "$tmp/jni/$arch/"
        done
    done

    # 重新打包
    (cd "$tmp" && zip -q -r "${ROOT}/${aar_name}" . -x "temp.aar")

    new_so=$(unzip -l "${ROOT}/${aar_name}" | grep -c "\.so" || true)
    rm -rf "$tmp"

    if [ "$new_so" -gt 0 ]; then
        echo "  -> 注入完成: ${has_so} -> ${new_so} 个 .so"
        injected_count=$((injected_count + 1))
    else
        echo "  -> 注入失败!"
    fi
done

echo ""
echo "共处理 ${injected_count} 个 AAR"
