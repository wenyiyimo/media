#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${ROOT_DIR}/release"
PACKAGE_NAME="media3-release-$(date +%Y%m%d-%H%M%S)"
PACKAGE_DIR="${OUTPUT_DIR}/${PACKAGE_NAME}"

echo "========================================="
echo " Media3 打包开始 (so 内置于 AAR)"
echo "========================================="

rm -rf "${PACKAGE_DIR}"
mkdir -p "${PACKAGE_DIR}/aar"

# ========== 1. 收集所有 library AAR ==========
echo "[1/2] 收集 AAR 文件..."
aar_count=0
while IFS= read -r aar_file; do
    cp "${aar_file}" "${PACKAGE_DIR}/aar/"
    aar_count=$((aar_count + 1))
done < <(find libraries -path "*/buildout/outputs/aar/*-release.aar" 2>/dev/null)

echo "  -> 已收集 ${aar_count} 个 AAR 文件"

# ========== 2. 生成索引 ==========
echo "[2/2] 生成索引..."

# AAR 列表
echo "AAR 列表:" > "${PACKAGE_DIR}/README.txt"
echo "=========================================" >> "${PACKAGE_DIR}/README.txt"
total_so=0
for aar in "${PACKAGE_DIR}/aar/"*.aar; do
    name=$(basename "$aar")
    size=$(du -h "$aar" | cut -f1)
    so_count=$(unzip -l "$aar" 2>/dev/null | grep -E '\.so$' | wc -l || true)
    total_so=$((total_so + so_count))
    echo "  ${name}  (${size})  [${so_count} .so]" >> "${PACKAGE_DIR}/README.txt"
done

echo "" >> "${PACKAGE_DIR}/README.txt"
echo "=========================================" >> "${PACKAGE_DIR}/README.txt"
echo "总 .so 文件数: ${total_so}" >> "${PACKAGE_DIR}/README.txt"
echo "总 AAR 文件数: ${aar_count}" >> "${PACKAGE_DIR}/README.txt"
echo "说明: .so 文件已内置于 AAR 的 jni/ 目录下" >> "${PACKAGE_DIR}/README.txt"

# 生成 JSON 索引
python3 -c "
import os, json, glob, subprocess

index = {'aar': [], 'so_by_aar': {}, 'total_so': 0}

for aar in sorted(glob.glob('${PACKAGE_DIR}/aar/*.aar')):
    size = os.path.getsize(aar)
    name = os.path.basename(aar)
    entry = {'file': name, 'size': size, 'size_human': f'{size/1024:.1f}KB'}

    # 提取 so 列表
    result = subprocess.run(['unzip', '-l', aar], capture_output=True, text=True)
    lines = result.stdout.split('\n')
    so_list = []
    so_by_lib = {}
    for line in lines:
        parts = line.strip().split()
        if len(parts) >= 4 and parts[-1].endswith('.so'):
            so_name = parts[-1]
            if 'jni/' in so_name:
                # 提取架构目录
                rel = so_name.replace('jni/', '')
                arch_dir = rel.split('/')[0]
                if arch_dir not in so_by_lib:
                    so_by_lib[arch_dir] = []
                so_by_lib[arch_dir].append(so_name)
                entry['_so_count'] = entry.get('_so_count', 0) + 1

    entry['so_archs'] = list(so_by_lib.keys())
    entry['so_count'] = len(so_by_lib)
    index['aar'].append(entry)
    index['so_by_aar'][name] = so_by_lib
    index['total_so'] += entry.get('_so_count', 0)

with open('${PACKAGE_DIR}/index.json', 'w') as f:
    json.dump(index, f, indent=2, ensure_ascii=False)
"

# ========== 3. 打包为 zip ==========
echo ""
echo "打包为 ${PACKAGE_NAME}.zip ..."
cd "${OUTPUT_DIR}"
zip -r "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"
cd "${ROOT_DIR}"

size=$(du -sh "${PACKAGE_DIR}" | cut -f1)

# ========== 4. 复制 release AAR 到固定目录 ==========
echo "[3/3] 复制 release AAR 到 ${OUTPUT_DIR}/aar/ ..."
rm -f "${OUTPUT_DIR}/aar/"*.aar
cp -f "${PACKAGE_DIR}/aar/"lib-*-release.aar "${OUTPUT_DIR}/aar/" 2>/dev/null || true
cp_count=$(ls "${OUTPUT_DIR}/aar/"/*.aar 2>/dev/null | wc -l)
echo "  -> 已复制 ${cp_count} 个 AAR 到 ${OUTPUT_DIR}/aar/"
echo ""
echo "========================================="
echo " 打包完成!"
echo " 输出目录: ${PACKAGE_DIR}"
echo " 压缩包:   ${OUTPUT_DIR}/${PACKAGE_NAME}.zip (${size})"
echo " release AAR: ${OUTPUT_DIR}/aar/ (${cp_count} 个)"
echo " AAR 数量: ${aar_count}"
echo " 总 .so:   ${total_so} (内置于 AAR 的 jni/ 目录)"
echo "========================================="
