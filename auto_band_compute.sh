#!/bin/bash
set -euo pipefail  #确保脚本在出错时能及时退出
# 加载环境变量
load_env() {
    source /home/ubuntu/intel/impi/2019.7.217/intel64/bin/mpivars.sh
    source /home/ubuntu/intel/bin/compilervars.sh intel64
    source /home/ubuntu/intel/bin/ifortvars.sh intel64
}
# 日志功能
log() {
    local message=$1
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $message"
}
# 处理单个文件
process_file() {
    local file=$1
    local base_name="${file%.*}"

    mkdir "$base_name"
    cd "$base_name" || exit

    log "处理文件: $file"
    mkdir opt scf dos band cube

    cd opt || exit
    cp "../../$file" ./

    log "使用Multiwfn将cif文件转换为POSCAR"
    echo -e "100\n2\n27\n\n0\nq" | Multiwfn ./*.cif >/dev/null

    log "创建INCAR和KPOINTS文件"
    (echo 1; echo 102; echo 1; echo 0.04) | vaspkit > out1.txt
    rm INCAR
    cp /home/ubuntu/app/template/band/opt0 ./INCAR

    log "开始结构优化"
    SECONDS=0
    mpirun -np 50 vasp_std > 1.log
    wait
    log "结构优化结束，耗时: $SECONDS 秒"
    if grep -q "reached required accuracy - stopping structural energy minimisation" OUTCAR || grep -q "reached ion step limit" OUTCAR; then
        log "结构优化正常完成/达到离子步上限，开始自洽场迭代"

        # 执行scf计算
        run_scf

        # 执行dos计算
        run_dos

        # 执行band计算
        run_band

        # 执行cube计算
        run_cube
    else
        log "结构优化未正常完成，不进行自洽场迭代"
    fi

    log "处理文件: $file 完成"
    cd ../../
}

# SCF计算
run_scf() {
    log "执行SCF计算"
    cd ../scf || exit
    cp ../opt/CONTCAR KPOINTS POTCAR ./
    mv CONTCAR POSCAR
    cp /home/ubuntu/app/template/band/scf0 ./INCAR
    mpirun -np 50 vasp_std > 1.log
    wait
    log "SCF计算完成"
}

# DOS计算
run_dos() {
    log "执行DOS计算"
    cd ../dos || exit
    cp ../scf/POSCAR KPOINTS POTCAR WAVECAR CHGCAR ./
    cp /home/ubuntu/app/template/band/dos ./INCAR
    mpirun -np 50 vasp_std > 1.log
    wait
    log "DOS计算完成"
    sumo-dosplot
}

# BAND计算
run_band() {
    log "执行BAND计算"
    cd ../band || exit
    cp ../scf/POSCAR POTCAR WAVECAR CHGCAR ./
    (echo 3; echo 303) | vaspkit > out3.txt
    rm INCAR
    cp /home/ubuntu/app/template/band/band0 ./INCAR
    if [ ! -f KPATH.in ]; then
        log "KPATH.in 文件不存在，空间群为三斜,KPOINTS文件从模板复制"
        cp /home/ubuntu/app/template/band/tri-KPOINTS ./KPOINTS
    elif [ -s KPATH.in ]; then
        log "KPATH.in 文件为空，跳过BAND计算"
        return
    else
        mv KPATH.in KPOINTS
        sed -i '2s/[0-9]\+/5/' KPOINTS
    fi
    mpirun -np 50 vasp_std > 1.log
    wait
    log "BAND计算完成"
    sumo-bandplot
    # 计算有效质量
    #amset plot band stats vasprun.xml
}

# CUBE计算
run_cube() {
    log "执行CUBE计算"
    cd ../cube || exit
    cp ../scf/POSCAR ./
    echo -e "cp2k\nfe.inp\n-3\n6\n2\n2\n0\nq" | Multiwfn ./POSCAR >/dev/null
    mpirun -np 50 -mca btl ^openib cp2k.popt fe.inp 1> cp2k.out 2> cp2k.err
    wait
    log "CUBE计算完成"
}

main() {
    load_env
    for file in *.cif; do
        process_file "$file"
    done
}
main "$@"
