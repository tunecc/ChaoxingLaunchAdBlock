#!/bin/bash
# ChaoxingLaunchAdBlock 统一打包入口
# 按 《越狱插件打包规范_rootful_rootless_roothide.md》实现:
#   - 官方原生 scheme 构建(rootful 显式清空 / rootless / roothide)
#   - 每 scheme 独立 package 目录,构建前清空,杜绝旧包混入
#   - 产物收敛到 out/,命名 <DisplayName>_<Version>_<Scheme>_<ShortArch>.deb
#   - dpkg-deb 包头核对 + 宿主元数据(.DS_Store/._*/__MACOSX)清洁性兜底
set -euo pipefail

# --- 项目定位(路径含空格时用引号保护;Theos 不支持空格路径,构建在无空格副本中进行) ---
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
project_name="$(basename "$repo_root")"

# --- 构建锁:同一项目同一时间只允许一个正式打包流程 ---
lock_dir="${TMPDIR:-/tmp}/${project_name}.build.lock"
while ! mkdir "$lock_dir" 2>/dev/null; do
    # 陈旧锁:持锁进程已不存在则清理
    if [ -f "$lock_dir/pid" ]; then
        old_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
        if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
            rm -rf "$lock_dir"
            continue
        fi
    fi
    echo "[build] waiting for lock: $lock_dir"
    sleep 2
done
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
echo $$ > "$lock_dir/pid"

# --- Theos:默认 /opt/theos,可用环境变量覆盖;必须支持 roothide scheme ---
THEOS="${THEOS:-/opt/theos}"
export THEOS
export PATH="$THEOS/bin:$PATH"

# --- 发布矩阵:按需启用,例如 ./scripts/build_packages.sh roothide 或 all ---
schemes="${1:-roothide}"
case "$schemes" in
    rootful|rootless|roothide|all) ;;
    *) echo "usage: $0 [rootful|rootless|roothide|all]" >&2; exit 2 ;;
esac
[ "$schemes" = "all" ] && schemes="rootful rootless roothide"

# --- 构建须在无空格路径下进行(Theos 限制) ---
src_dir="$repo_root"
staging_root="$(mktemp -d "${TMPDIR:-/tmp}/cxbuild.XXXXXX")"
trap 'rmdir "$lock_dir" 2>/dev/null || true; rm -rf "$staging_root"' EXIT

cleanup_host_metadata() {
    local target_path
    for target_path in "$@"; do
        [ -e "$target_path" ] || continue
        find "$target_path" -type f \( -name '.DS_Store' -o -name '._*' \) -exec rm -f {} +
        find "$target_path" -name '__MACOSX' -type d -prune -exec rm -rf {} +
    done
}

out_dir="$repo_root/out"
mkdir -p "$out_dir"
rm -f "${out_dir}"/*.deb   # out/ 只保留本次构建产物

version="$(sed -n 's/^Version: //p' "$src_dir/control" | head -n1 | tr -d '[:space:]')"
[ -n "$version" ] || { echo "[build] cannot read Version from control" >&2; exit 1; }

for scheme in $schemes; do
    echo "[build] ===== scheme: $scheme ====="
    work_dir="$staging_root/$scheme"
    mkdir -p "$work_dir"
    # 源文件同步:仅构建所需文件,避免带入 .DS_Store 等宿主元数据
    tar -C "$src_dir" -cf - Makefile control Tweak.xm ChaoxingLaunchAdBlock.plist | tar -C "$work_dir" -xf -
    cd "$work_dir"

    case "$scheme" in
        rootful)  package_args=(FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=) ;;
        rootless) package_args=(FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless) ;;
        roothide) package_args=(FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide) ;;
    esac

    # 每 scheme 独立 package 输出目录,构建前清空(规范 11.2)
    pkg_dir="$work_dir/packages/$scheme"
    rm -rf "$pkg_dir"
    package_dir_env="THEOS_PACKAGE_DIR=$pkg_dir"

    if [ "$scheme" = "rootful" ]; then
        make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME= THEOS_PACKAGE_DIR="$pkg_dir"
    else
        make clean package FINALPACKAGE=1 "THEOS_PACKAGE_SCHEME=$scheme" THEOS_PACKAGE_DIR="$pkg_dir"
    fi

    # 目录里只应有一个本次生成的 deb
    deb_count="$(find "$pkg_dir" -name '*.deb' | wc -l | tr -d ' ')"
    [ "$deb_count" = "1" ] || { echo "[build] $scheme: expected 1 deb, got $deb_count" >&2; exit 1; }
    built_deb="$(find "$pkg_dir" -name '*.deb')"

    case "$scheme" in
        rootful)  short_arch="arm" ;;
        rootless) short_arch="arm64" ;;
        roothide) short_arch="arm64e" ;;
    esac
    # 从包头读取 Version/Architecture 核对
    pkg_ver="$(dpkg-deb -f "$built_deb" Version | tr -d '[:space:]')"
    pkg_arch="$(dpkg-deb -f "$built_deb" Architecture | tr -d '[:space:]')"
    case "$scheme" in
        rootful)  expected_arch="iphoneos-arm" ;;
        rootless) expected_arch="iphoneos-arm64" ;;
        roothide) expected_arch="iphoneos-arm64e" ;;
    esac
    [ "$pkg_ver" = "$version" ] || { echo "[build] version mismatch: control=$version deb=$pkg_ver" >&2; exit 1; }
    [ "$pkg_arch" = "$expected_arch" ] || { echo "[build] $scheme: arch mismatch: want=$expected_arch got=$pkg_arch" >&2; exit 1; }

    out_deb="${out_dir}/ChaoxingLaunchAdBlock_${version}_${scheme}_${short_arch}.deb"
    cp "$built_deb" "$out_deb"

    # 宿主元数据清洁性兜底(规范 10.5)
    unpack_dir="$(mktemp -d "${TMPDIR:-/tmp}/cxcheck.XXXXXX")"
    dpkg-deb -R "$out_deb" "$unpack_dir"
    cleanup_host_metadata "$unpack_dir"
    # 修正包内常规文件权限为 root 可读 (644/755),避免宿主 600 权限进包
    find "$unpack_dir" -type f -name '*.plist' -exec chmod 644 {} +
    find "$unpack_dir" -type f -name '*.dylib' -exec chmod 755 {} +
    find "$unpack_dir/DEBIAN" -type f -exec chmod 644 {} + 2>/dev/null || true
    rm -f "$out_deb"
    dpkg-deb -b --root-owner-group "$unpack_dir" "$out_deb"
    rm -rf "$unpack_dir"

    # 最终核对:文件名与包头一致
    dpkg-deb -f "$out_deb" Package Version Architecture
    echo "[build] => $out_deb"
    # 解包验收:不出现跨 scheme 语义污染 rootful: no var/jb; rootless: must have var/jb; roothide: no var/jb root
    verify_dir="$(mktemp -d "${TMPDIR:-/tmp}/cxverify.XXXXXX")"
    dpkg-deb -R "$out_deb" "$verify_dir"
    if [ "$scheme" = "rootless" ]; then
        [ -d "$verify_dir/var/jb" ] || { echo "[build] rootless: var/jb missing" >&2; exit 1; }
    else
        [ -d "$verify_dir/var/jb" ] && { echo "[build] $scheme: unexpected var/jb root" >&2; exit 1; }
    fi
    metadata_check="$(find "$verify_dir" \( -name '.DS_Store' -o -name '._*' -o -name '__MACOSX' \) | wc -l | tr -d ' ')"
    [ "$metadata_check" = "0" ] || { echo "[build] host metadata leaked into package" >&2; exit 1; }
    rm -rf "$verify_dir"
done

echo "[build] done. artifacts:"
ls -la "${out_dir}"/*.deb
