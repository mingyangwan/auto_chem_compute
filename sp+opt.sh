#!/bin/bash
# opt+sp计算
set -euo pipefail
#用法 在包含 .mol 文件的目录中运行脚本： ./run_gaussian.sh
# 日志功能
log() {
    local message=$1
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $message"
}
# 结构优化
optimize_structure() {
    local file=$1
    local index=$2
    local total_files=$3

    mkdir "$index"
    cd "$index" || exit
    cp "$file" ./
    local base_name="${file##*/}"
    local gjf_file="${base_name//mol/gjf}"
    local out_file="${base_name//mol/out}"

    log "Converting ${file} to ${gjf_file} ... ($index of $total_files)"
    echo -e "100\n2\n10\n${gjf_file}\n0\nq" | Multiwfn "$file" >/dev/null #默认使用B3LYP优化
    log "Running ${file} ... ($index of $total_files)"
    time g16 -p=50 -m="100GB" <"${gjf_file}" >"${out_file}"
# 判断优化是否成功
    if grep -q "Optimization completed" "${out_file}"; then
        log "Optimization of ${file} completed successfully, proceeding with SCF calculation..."
        mkdir scf
        cp "${out_file}" ./scf
        cd scf || exit
        run_scf "${out_file}"
    else
        log "Optimization of ${file} did not complete successfully, skipping SCF calculation."
    fi
    log "${file} compute has finished"
    cd ../..
}

# SCF计算
run_scf() {
    local out_file=$1

    for j in ./*.out; do
        local gjf_file="${j//out/gjf}"
        log "Converting ${j} to ${gjf_file} ..."
        echo -e "100\n2\n10\n${gjf_file}\n0\nq" | Multiwfn "$j" >/dev/null
        rm "$j"
        sed -i "s/B3LYP/M062X/g" "${gjf_file}" # 替换B3LYP为M062X，根据自己要求替换
        log "Converting B3LYP to M062X for ${j} SCF calculation"
        time g16 -p=50 -m="100GB" < "${gjf_file}" >"$j"
        formchk "${j//out/chk}"
        echo -e "200\n3\nh,l\n2\n2\n0\nq" | Multiwfn "${j//out/fch}" >/dev/null # 生成cube文件
    done
}

main() {
    local icc=0
    local total_files=$(find . -name "*.mol" | wc -l)

    for file in ./*.mol; do
        ((icc++))
        optimize_structure "$file" "$icc" "$total_files"
    done
}

main "$@"
