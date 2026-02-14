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
    
    # OpenCode は `.opencode/commands`, `.opencode/agents`, `.opencode/skills`, `.opencode/plugins` を読み込む。
    # `.opencode/rules` は探索対象ではないため生成しない。
    # Ref:
    # - Commands: https://opencode.ai/docs/commands/
    # - Agents: https://opencode.ai/docs/agents/
    # - Skills: https://opencode.ai/docs/skills/
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] mkdir -p $target_dir/commands $target_dir/agents $target_dir/skills $target_dir/plugins"
        log_info "[DRY-RUN] generate commands from .agent/commands -> $target_dir/commands (init.md -> sdd-init.md)"
        log_info "[DRY-RUN] generate agent(s) from .agent/agents -> $target_dir/agents (frontmatter added)"
        log_info "[DRY-RUN] generate skills from skills/*.md and .agent/rules/*.md -> $target_dir/skills/*/SKILL.md"
        log_info "[DRY-RUN] generate plugins -> $target_dir/plugins"
        return
    fi

    mkdir -p "$target_dir/commands" "$target_dir/agents" "$target_dir/skills" "$target_dir/plugins"

    # Legacy cleanup (older versions of this repo generated these paths)
    # Avoid running rm unless the path actually exists (helps reduce unnecessary prompts).
    if [ -d "$target_dir/rules" ]; then
        rm -rf "$target_dir/rules"
    fi
    if [ -f "$target_dir/commands/init.md" ]; then
        rm -f "$target_dir/commands/init.md"
    fi
    if [ -f "$target_dir/agents/reviewer.md" ]; then
        rm -f "$target_dir/agents/reviewer.md"
    fi

    # -----------------
    # Commands
    # -----------------
    if [ -d ".agent/commands" ]; then
        for cmd_file in .agent/commands/*.md; do
            [ -f "$cmd_file" ] || continue

            local cmd_base
            cmd_base=$(basename "$cmd_file" .md)

            local target_name="$cmd_base"
            local cmd_description="Agentic-SDD command: $cmd_base"
            local cmd_agent="build"

            case "$cmd_base" in
                init)
                    # OpenCode built-in `/init` generates AGENTS.md.
                    # Avoid overriding it; expose Agentic-SDD init as `/sdd-init`.
                    target_name="sdd-init"
                    cmd_description="Initialize Agentic-SDD workflow files in a project"
                    ;;
                create-prd)
                    cmd_description="Create a PRD via 7 questions and checks"
                    ;;
                create-epic)
                    cmd_description="Create an epic from a PRD (3 required lists)"
                    ;;
                create-issues)
                    cmd_description="Create issues from an epic (granularity rules)"
                    ;;
                estimation)
                    cmd_description="Create a Full estimate (11 sections) and approval gate"
                    ;;
                impl)
                    cmd_description="Implement an issue (normal mode) after estimation"
                    ;;
                tdd)
                    cmd_description="Implement an issue via strict TDD (Red -> Green -> Refactor)"
                    ;;
                final-review)
                    cmd_description="Final review with DoD and sync-docs"
                    cmd_agent="sdd-reviewer"
                    ;;
                review-cycle)
                    cmd_description="Run local review cycle (codex exec -> review.json)"
                    ;;
                sync-docs)
                    cmd_description="Check PRD/Epic/code consistency (sync-docs)"
                    ;;
                create-pr)
                    cmd_description="Push branch and create a Pull Request via gh"
                    ;;
                codex-pr-review)
                    cmd_description="Request a Codex bot PR review (@codex review) and iterate until resolved"
                    ;;
                worktree)
                    cmd_description="Manage git worktrees for parallel Issues"
                    ;;
            esac

            local target_cmd_file="$target_dir/commands/$target_name.md"
            {
                cat << EOF
---
description: $cmd_description
agent: $cmd_agent
---
EOF
                if [ "$cmd_base" = "init" ]; then
                    cat << 'EOF'
Note: OpenCode has a built-in `/init` (generates AGENTS.md). To avoid conflicts, this command is provided as `/sdd-init`.

EOF
                fi
                cat "$cmd_file"
            } > "$target_cmd_file"
        done
    fi

    # -----------------
    # Skills
    # -----------------
    generate_skill_from_file() {
        local skill_name="$1"
        local skill_description="$2"
        local source_file="$3"

        [ -f "$source_file" ] || return 0

        local skill_dir="$target_dir/skills/$skill_name"
        mkdir -p "$skill_dir"

        {
            cat << EOF
---
name: $skill_name
description: >-
  $skill_description
compatibility: opencode
---
EOF
            cat "$source_file"
        } > "$skill_dir/SKILL.md"
    }

    # Project design skills
    generate_skill_from_file "sdd-estimation" "Full estimation (11 sections) and confidence rules" "skills/estimation.md"
    generate_skill_from_file "sdd-worktree-parallel" "Parallel implementation with git worktree (deterministic guardrails)" "skills/worktree-parallel.md"
    generate_skill_from_file "sdd-anti-patterns" "AI failure patterns and safer alternatives" "skills/anti-patterns.md"
    generate_skill_from_file "sdd-api-endpoint" "REST API endpoint design checklist" "skills/api-endpoint.md"
    generate_skill_from_file "sdd-crud-screen" "CRUD screen design checklist" "skills/crud-screen.md"
    generate_skill_from_file "sdd-data-driven" "Data-driven development (metrics and evidence)" "skills/data-driven.md"
    generate_skill_from_file "sdd-error-handling" "Error classification, handling, and logging guidelines" "skills/error-handling.md"
    generate_skill_from_file "sdd-resource-limits" "Resource limits to prevent runaway processes" "skills/resource-limits.md"
    generate_skill_from_file "tdd-testing" "Test strategy, pyramid, and coverage guidance" "skills/testing.md"
    generate_skill_from_file "tdd-protocol" "TDD execution protocol, legacy refactor tactics, and determinism seams" "skills/tdd-protocol.md"

    # Agentic-SDD rules (loaded on-demand via the skill tool)
    generate_skill_from_file "sdd-rule-docs-sync" "Rules for keeping PRD, Epic, and code in sync" ".agent/rules/docs-sync.md"
    generate_skill_from_file "sdd-rule-dod" "Definition of Done checklist" ".agent/rules/dod.md"
    generate_skill_from_file "sdd-rule-impl-gate" "Implementation gate rules (estimate/test/quality)" ".agent/rules/impl-gate.md"
    generate_skill_from_file "sdd-rule-epic" "Epic generation constraints and checklists" ".agent/rules/epic.md"
    generate_skill_from_file "sdd-rule-issue" "Issue granularity rules and exception labels" ".agent/rules/issue.md"
    generate_skill_from_file "sdd-rule-branch" "Git branch naming rules" ".agent/rules/branch.md"
    generate_skill_from_file "sdd-rule-commit" "Conventional Commits message rules" ".agent/rules/commit.md"
    generate_skill_from_file "sdd-rule-datetime" "Date/time formatting rules" ".agent/rules/datetime.md"

    # -----------------
    # Agents
    # -----------------
    if [ -f ".agent/agents/reviewer.md" ]; then
        {
            cat << 'EOF'
---
description: Reviews PRs/issues with Agentic-SDD DoD and sync-docs
mode: subagent
model: openai/gpt-5.3-codex
reasoningEffort: high
temperature: 0.1
tools:
  write: false
  edit: false
---
EOF
            cat ".agent/agents/reviewer.md"
            cat << 'EOF'

---

## Notes (OpenCode)

When needed, load these skills:

- sdd-rule-dod
- sdd-rule-docs-sync
EOF
        } > "$target_dir/agents/sdd-reviewer.md"
    fi

    if [ -f ".agent/agents/docs.md" ]; then
        {
            cat << 'EOF'
---
description: Generate minimal Agentic-SDD context packs
mode: primary
model: anthropic/claude-sonnet-4-5
temperature: 0.0
maxSteps: 4
tools:
  write: false
  edit: false
  bash: false
  webfetch: false
---
EOF
            cat ".agent/agents/docs.md"
        } > "$target_dir/agents/sdd-docs.md"

        # Backward-compat cleanup (previously generated).
        rm -f "$target_dir/agents/sdd-docs-primary.md"
    fi

    # -----------------
    # Plugins
    # -----------------
    # Gate enforcement to prevent accidental implementation before estimation approval.
    # Loaded automatically by OpenCode at startup when placed under `.opencode/plugins/`.
    cat > "$target_dir/plugins/agentic-sdd-gate.js" <<'EOF'
export const AgenticSddGatePlugin = async ({ $, worktree }) => {
  const isAllowedPath = (path) => {
    if (typeof path !== "string" || path.length === 0) return false
    const p = path.replace(/\\/g, "/")
    return p === ".agentic-sdd" || p.startsWith(".agentic-sdd/") || p.includes("/.agentic-sdd/")
  }

  const getPathFromArgs = (args) => {
    if (!args || typeof args !== "object") return undefined
    const keys = ["path", "file", "file_path", "filePath", "filepath", "filename", "target"]
    for (const k of keys) {
      const v = args[k]
      if (typeof v === "string" && v.length > 0) return v
    }
    return undefined
  }

  const isGitCommitOrPush = (cmd) => {
    if (typeof cmd !== "string") return false
    const s = cmd.trim()
    return s.startsWith("git commit") || s.startsWith("git push")
  }

  const validate = async () => {
    await $`cd ${worktree} && python3 scripts/validate-worktree.py`
    await $`cd ${worktree} && python3 scripts/validate-approval.py`
  }

  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool === "edit" || input.tool === "write") {
        const p = getPathFromArgs(output.args)
        if (isAllowedPath(p)) {
          await $`cd ${worktree} && python3 scripts/validate-worktree.py`
          return
        }
        await validate()
        return
      }

      if (input.tool === "bash") {
        const cmd = output.args?.command ?? output.args?.cmd ?? output.args?.script
        if (!isGitCommitOrPush(cmd)) return
        await validate()
      }
    },
  }
}
EOF

    log_info "OpenCode への同期が完了しました"
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
