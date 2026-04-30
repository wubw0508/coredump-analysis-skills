#!/bin/bash
#=============================================================================
# 深度自动化崩溃分析 + 修复提交
#=============================================================================

set -e

SKILLS_DIR="${SKILLS_DIR:-$HOME/.openclaw/skills/coredump-analysis-skills}"
SCRIPTS_DIR="$SKILLS_DIR/coredump-full-analysis/scripts"
TARGET_BRANCH="origin/develop/eagle"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --target-branch) TARGET_BRANCH="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

if [[ -z "$WORKSPACE" ]]; then
    echo "错误: 必须指定 --workspace"
    exit 1
fi

FIXABLE_PROJECTS=("dde-dock" "dde-launcher" "dde-control-center")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

fix_version() {
    local package="$1"
    local version="$2"
    
    log "处理: $package $version"
    
    cd "$SCRIPTS_DIR"
    local cmd="python3 deep_auto_fix.py --package $package --version $version --workspace $WORKSPACE --target-branch $TARGET_BRANCH"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        cmd="$cmd --dry-run"
    fi
    
    log "  执行: $cmd"
    
    if eval "$cmd" 2>&1; then
        log "  ✅ 深度自动修复完成"
        return 0
    else
        log "  ❌ 深度自动修复失败"
        return 1
    fi
}

fix_package() {
    local package="$1"
    local analysis_dir="$WORKSPACE/5.崩溃分析/$package"
    
    if [[ ! -d "$analysis_dir" ]]; then
        log "跳过 $package: 分析目录不存在"
        return 0
    fi
    
    log "========================================"
    log "处理项目: $package"
    log "========================================"
    
    local version_dirs=$(find "$analysis_dir" -name "version_*" -type d 2>/dev/null)
    
    if [[ -z "$version_dirs" ]]; then
        log "  未找到版本目录"
        return 0
    fi
    
    local success_count=0
    local fail_count=0
    
    for version_dir in $version_dirs; do
        local version=$(basename "$version_dir" | sed 's/version_//' | sed 's/_/./g')
        
        if fix_version "$package" "$version"; then
            ((success_count++)) || true
        else
            ((fail_count++)) || true
        fi
    done
    
    log "  $package 处理完成: 成功=$success_count, 失败=$fail_count"
}

main() {
    log "================================================================"
    log "深度自动化崩溃分析 + 修复提交"
    log "================================================================"
    log "工作目录: $WORKSPACE"
    log "目标分支: $TARGET_BRANCH"
    log "干运行: $DRY_RUN"
    log "================================================================"
    
    local total_success=0
    local total_fail=0
    
    for package in "${FIXABLE_PROJECTS[@]}"; do
        if fix_package "$package"; then
            ((total_success++)) || true
        else
            ((total_fail++)) || true
        fi
        echo ""
    done
    
    log "================================================================"
    log "处理完成"
    log "================================================================"
    log "成功项目: $total_success"
    log "失败项目: $total_fail"
}

main
