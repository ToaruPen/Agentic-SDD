#!/bin/bash

# sync-agent-config.sh
# .agent/ を正本として、各ツール用の設定ディレクトリに同期するスクリプト
#
# 対応ツール:
# - Codex CLI (.codex/)
# - OpenCode (.opencode/)
# - Claude Code (.agent/ をそのまま使用)

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ヘルプ表示
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [TARGETS...]

.agent/ を正本として、各ツール用の設定ディレクトリに同期します。

TARGETS:
  codex       Codex CLI (.codex/) に同期
  opencode    OpenCode (.opencode/) に同期
  all         すべてのツールに同期（デフォルト）

OPTIONS:
  -h, --help      このヘルプを表示
  -n, --dry-run   実際には同期せず、実行内容を表示
  -f, --force     確認なしで上書き
  -c, --clean     同期前に対象ディレクトリをクリーン

EXAMPLES:
  $(basename "$0")              # すべてのツールに同期
  $(basename "$0") codex        # Codex CLI のみに同期
  $(basename "$0") --dry-run    # 実行内容のプレビュー
  $(basename "$0") --clean all  # クリーンしてから同期

EOF
}

# 引数解析
DRY_RUN=false
FORCE=false
CLEAN=false
TARGETS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        codex|opencode|all)
            TARGETS+=("$1")
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# デフォルトは all
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=("all")
fi

# all の場合は展開
if [[ " ${TARGETS[*]} " =~ " all " ]]; then
    TARGETS=("codex" "opencode")
fi

# プロジェクトルートの確認
if [ ! -d ".agent" ]; then
    log_error ".agent/ ディレクトリが見つかりません。プロジェクトルートで実行してください。"
    exit 1
fi

# Codex CLI 用の同期
sync_codex() {
    log_info "Codex CLI (.codex/) に同期中..."
    
    local target_dir=".codex"
    
    if [ "$CLEAN" = true ] && [ -d "$target_dir" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] rm -rf $target_dir"
        else
            rm -rf "$target_dir"
            log_info "$target_dir をクリーンしました"
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] mkdir -p $target_dir"
        log_info "[DRY-RUN] cp -r .agent/commands/* $target_dir/"
        log_info "[DRY-RUN] cp -r .agent/rules/* $target_dir/"
    else
        mkdir -p "$target_dir"
        
        # Codex CLI は commands/ と rules/ をフラットに配置
        if [ -d ".agent/commands" ]; then
            cp -r .agent/commands/* "$target_dir/" 2>/dev/null || true
        fi
        if [ -d ".agent/rules" ]; then
            cp -r .agent/rules/* "$target_dir/" 2>/dev/null || true
        fi
        
        log_info "Codex CLI への同期が完了しました"
    fi
}

# OpenCode 用の同期
sync_opencode() {
    log_info "OpenCode (.opencode/) に同期中..."
    
    local target_dir=".opencode"
    
    if [ "$CLEAN" = true ] && [ -d "$target_dir" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] rm -rf $target_dir"
        else
            rm -rf "$target_dir"
            log_info "$target_dir をクリーンしました"
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] mkdir -p $target_dir/commands $target_dir/rules $target_dir/agents"
        log_info "[DRY-RUN] cp -r .agent/commands/* $target_dir/commands/"
        log_info "[DRY-RUN] cp -r .agent/rules/* $target_dir/rules/"
        log_info "[DRY-RUN] cp -r .agent/agents/* $target_dir/agents/"
    else
        mkdir -p "$target_dir/commands" "$target_dir/rules" "$target_dir/agents"
        
        # OpenCode は .agent/ と同じ構造
        if [ -d ".agent/commands" ]; then
            cp -r .agent/commands/* "$target_dir/commands/" 2>/dev/null || true
        fi
        if [ -d ".agent/rules" ]; then
            cp -r .agent/rules/* "$target_dir/rules/" 2>/dev/null || true
        fi
        if [ -d ".agent/agents" ]; then
            cp -r .agent/agents/* "$target_dir/agents/" 2>/dev/null || true
        fi
        
        log_info "OpenCode への同期が完了しました"
    fi
}

# 確認プロンプト
confirm_sync() {
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo ""
    log_warn "以下のディレクトリに同期します:"
    for target in "${TARGETS[@]}"; do
        case $target in
            codex)
                echo "  - .codex/"
                ;;
            opencode)
                echo "  - .opencode/"
                ;;
        esac
    done
    echo ""
    read -p "続行しますか？ (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log_info "キャンセルしました"
            exit 0
            ;;
    esac
}

# メイン処理
main() {
    log_info "Agentic-SDD 設定同期スクリプト"
    log_info "正本: .agent/"
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY-RUN モード: 実際の変更は行いません"
    fi
    
    confirm_sync
    
    for target in "${TARGETS[@]}"; do
        case $target in
            codex)
                sync_codex
                ;;
            opencode)
                sync_opencode
                ;;
        esac
    done
    
    echo ""
    log_info "同期が完了しました"
    
    # Claude Code への注意
    echo ""
    log_info "注意: Claude Code は .agent/ をそのまま使用するため、同期不要です。"
}

main
