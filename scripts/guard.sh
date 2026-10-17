#!/usr/bin/env bash
# 并行开发门禁：Phase 5 的唯一可信证据。
# 注释中的 [gate N] 对应《全栈并行开发完整方案》(references/fullstack.md) §8 清单编号。
# 本脚本直接实现 §8 第 1-6,8,10-14 项，并按项目能力调度 15(eslint)/19(build)/20(unit)/21(e2e)。
# 未实现、需接项目已有工具：7 schema-drift / 9 contract-test / 16 lint-sql / 17 secret-scan /
#   18 dep-audit / 22 越权用例 / 23 perf smoke（各 step 的 SKIP 提示给出接入点）。
# 21 的「状态机节点数 vs e2e 用例数」比对无现成脚本，需自建映射（见 fullstack.md §8 说明）。
# 用法：
#   BASE_REF=main ./scripts/guard.sh        # 全部门禁（始终全链，不支持单项参数）
#   RUN_AS_AGENT=impl-1 BASE_REF=main ./scripts/guard.sh   # ownership 按单一 agent 归属校验（并行期推荐）
#   单项调试直接跑对应脚本：node scripts/dedup.mjs / node scripts/dup-check.mjs /
#                          SCAN_ALL=1 node scripts/authz-coverage.mjs
# 环境变量：
#   BASE_REF           diff 基线（默认 origin/main）。无效值 = 直接 FAIL，不静默通过。
#   RUN_AS_AGENT       设置后 ownership-guard 只认该 agent 的 glob（否则用全体并集并告警局限）。
#   ALLOW_READONLY_TOUCH=1  显式放行只读路径改动（Contract Owner / Integrator 提交时用）。
#   AUTHZ_STRICT=0     把 authz 缺失从 FAIL 降为 WARN（默认严格 FAIL；仅调试期放宽）。
#   MAX_DIFF_LINES     pr-size 上限（默认 800；测的是 BASE_REF...HEAD 分支累计 diff，
#                      单任务粒度需每任务独立分支或独立 BASE）。
#   MIGRATIONS_DIR / OPENAPI_SPEC / SERVER_DIR / SRC_DIR / DUP_THRESHOLD / STUB_MARKER  见各 step。
# 依赖：git、node；可选 pnpm 或 npm（缺则 14/15/19/20/21 项 SKIP 而非误报）。
# 任一检查失败 → 非零退出，本轮不通过。

set -uo pipefail
BASE_REF="${BASE_REF:-origin/main}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0
step() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  [PASS] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=1; }
warn() { printf '  [WARN] %s\n' "$1"; }

# ---------- 基线解析：无效 BASE_REF 必须显式失败，绝不静默放行 ----------
DIFF_OK=0
CHANGED=""
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  bad "不是 git 仓库 —— diff 类门禁（contract/ownership/deps/migration）不可用"
elif ! git rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null 2>&1; then
  bad "BASE_REF='$BASE_REF' 不存在或不可解析 —— 拒绝静默通过；请设置有效基线（如 BASE_REF=main）"
else
  DIFF_OK=1
  # -M 检测重命名：搬离只读路径的 rename 同时输出旧路径与新路径，堵住「git mv 绕过 contract-guard」
  CHANGED=$(git diff --name-status -M "$BASE_REF"...HEAD 2>/dev/null | awk -F'\t' '{ if ($1 ~ /^R/) { print $2; print $3 } else { print $2 } }')
  if [ -z "$CHANGED" ]; then
    CHANGED=$(git diff --name-status -M --staged 2>/dev/null | awk -F'\t' '{ if ($1 ~ /^R/) { print $2; print $3 } else { print $2 } }')
  fi
  # 未提交/未跟踪改动提示：gate 只审计已提交内容，工作区脏状态需 Coordinator 知情
  DIRTY=$(git status --porcelain 2>/dev/null | head -10)
  if [ -n "$DIRTY" ]; then
    warn "存在未提交/未跟踪改动（不在本次 diff 审计范围内，提交后重跑 gate）："
    printf '%s\n' "$DIRTY" | sed 's/^/    /'
  fi
fi

# [gate 1] contract-guard — 契约、横切层与治理文件禁止写入
# 治理文件（ownership.tsv / 号段表 / 门禁脚本自身）也在只读清单：受约束的 agent 不得自我扩权或改门禁。
step "contract-guard"
READONLY_PATTERNS=(
  '^src/contracts/'
  '^src/theme/'
  '^src/api/client'
  '^src/store/index\.(ts|js)$'
  '^src/app/routes\.(tsx|ts)$'
  '^package\.json$'
  '^pnpm-lock\.yaml$'
  '^package-lock\.json$'
  '^yarn\.lock$'
  '^tsconfig'
  '^docs/plan/ownership\.tsv$'
  '^docs/plan/migration-ranges\.tsv$'
  '^docs/plan/routes\.expected\.json$'
  '^scripts/(guard\.sh|dedup\.mjs|dup-check\.mjs|authz-coverage\.mjs)$'
)
HIT=""
if [ "$DIFF_OK" -eq 1 ] && [ -n "$CHANGED" ]; then
  for p in "${READONLY_PATTERNS[@]}"; do
    m=$(printf '%s\n' "$CHANGED" | grep -E "$p" || true)
    [ -n "$m" ] && HIT="$HIT$m"$'\n'
  done
fi
if [ -n "$HIT" ]; then
  if [ "${ALLOW_READONLY_TOUCH:-}" = "1" ]; then
    ok "readonly paths touched (explicitly allowed)"
    printf '%s' "$HIT" | sed 's/^/    /'
  else
    bad "readonly paths were modified during parallel phase:"
    printf '%s' "$HIT" | sed 's/^/    /'
    echo "  → 走 CONTRACT_REQUEST，由 Contract Owner 统一修改并广播版本；治理文件（ownership/号段/门禁脚本）只有 Coordinator 可改"
  fi
else
  ok "no readonly path touched"
fi

# [gate 2] ownership-guard — 越界写入
#    docs/plan/ownership.tsv 格式：  <agent-id> <TAB> <glob>   （一行一条，# 开头为注释，CRLF 自动容忍）
#    默认（并集模式）只查「改动被某个 glob 覆盖」，不区分是哪个 agent 改的——共享分支时 A 改 B 目录也会
#    PASS。并行期请让每个任务提交前跑 RUN_AS_AGENT=<自己的id>，或每任务独立分支。
step "ownership-guard"
OWNERSHIP="docs/plan/ownership.tsv"
if [ ! -f "$OWNERSHIP" ]; then
  bad "$OWNERSHIP not found"
elif [ "$DIFF_OK" -ne 1 ]; then
  echo "  [SKIP] 无有效 diff 基线"
else
  OWN_ROWS=$(tr -d '\r' < "$OWNERSHIP" | grep -vE '^\s*#' | grep -vE '^\s*$' || true)
  if [ -z "$OWN_ROWS" ]; then
    bad "$OWNERSHIP 无有效条目"
  else
    # 2a. 两两重叠检测：glob 去掉尾部 * 后的基目录互为前缀 = 重叠（独占承诺的前提）
    OVERLAP=$(printf '%s\n' "$OWN_ROWS" | awk -F'\t' '
      { base=$2; sub(/\*+$/,"",base); g[i++]= $1 "\t" base }
      END { for (a=0;a<i;a++) for (b=a+1;b<i;b++) {
          split(g[a],x,"\t"); split(g[b],y,"\t");
          if (x[1]!=y[1] && (index(y[2],x[2])==1 || index(x[2],y[2])==1))
            print x[1] "(" x[2] ") 与 " y[1] "(" y[2] ")"
        } }')
    if [ -n "$OVERLAP" ]; then
      bad "ownership glob 两两重叠（并行前提是互不重叠）："
      printf '%s\n' "$OVERLAP" | sed 's/^/    /'
    fi
    # 2b. 覆盖检查
    if [ -n "${RUN_AS_AGENT:-}" ]; then
      ALLOW=$(printf '%s\n' "$OWN_ROWS" | awk -F'\t' -v who="$RUN_AS_AGENT" '$1==who {print $2}')
      if [ -z "$ALLOW" ]; then
        bad "RUN_AS_AGENT='$RUN_AS_AGENT' 在 ownership.tsv 中无登记"
      fi
    else
      ALLOW=$(printf '%s\n' "$OWN_ROWS" | awk -F'\t' '{print $2}' | sort -u)
      warn "并集模式：不校验改动归属哪个 agent（A 改 B 目录也会 PASS）。并行期建议 RUN_AS_AGENT=<id> 或每任务独立分支"
    fi
    VIOL=""
    if [ -n "$ALLOW" ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in
          docs/*|scripts/*|tests/e2e/*|.github/*) continue ;;   # 公共基建目录豁免（治理文件已由 gate 1 保护）
        esac
        covered=0
        while IFS= read -r g; do
          [ -z "$g" ] && continue
          case "$f" in $g) covered=1; break ;; esac
        done <<< "$ALLOW"
        [ "$covered" -eq 0 ] && VIOL="$VIOL$f"$'\n'
      done <<< "$CHANGED"
    fi
    if [ -n "$VIOL" ]; then
      bad "files outside declared ownership scope:"
      printf '%s' "$VIOL" | sed 's/^/    /'
    else
      ok "all changes within ownership scope"
    fi
  fi
fi

# [gate 3] deps-guard — 依赖冻结
step "deps-guard"
if [ "$DIFF_OK" -eq 1 ] && [ -n "$CHANGED" ] && printf '%s\n' "$CHANGED" | grep -qE '^package\.json$|^pnpm-lock\.yaml$|^package-lock\.json$|^yarn\.lock$'; then
  if [ "${ALLOW_READONLY_TOUCH:-}" = "1" ]; then ok "deps changed (explicitly allowed)"; else
    bad "dependency added/changed during parallel phase"
  fi
else
  ok "deps untouched"
fi

# [gate 13] route-snapshot — 路由清单快照（方案 B 必备；方案 A 也建议保留）
step "route-snapshot"
if [ -f scripts/gen-routes.mjs ]; then
  ROUTES_ACTUAL=$(mktemp)   # mktemp 原子创建，杜绝固定路径符号链接改写任意文件
  if node scripts/gen-routes.mjs > "$ROUTES_ACTUAL" 2>/dev/null; then
    if [ -f docs/plan/routes.expected.json ]; then
      if diff -q "$ROUTES_ACTUAL" docs/plan/routes.expected.json >/dev/null 2>&1; then
        ok "route manifest matches plan"
      else
        bad "route manifest drift (actual vs expected):"
        diff docs/plan/routes.expected.json "$ROUTES_ACTUAL" | sed 's/^/    /'
      fi
    else
      echo "  [SKIP] docs/plan/routes.expected.json 不存在，首次运行请执行:"
      echo "         node scripts/gen-routes.mjs > docs/plan/routes.expected.json"
    fi
  else
    bad "route generator failed"
  fi
  rm -f "$ROUTES_ACTUAL"
else
  echo "  [SKIP] 未使用约定式路由生成器"
fi

# [gate 10] dedup-check — 语义去重：同一路由 path 重复注册、同名导出、重复埋点 key
step "dedup-check"
node scripts/dedup.mjs 2>&1 | sed 's/^/    /' || bad "dedup found conflicts"

# [gate 12] stub-count — stub 归零（标记字符串可由项目约定，默认 PLACEHOLDER_STUB）
step "stub-count"
STUB_MARKER="${STUB_MARKER:-PLACEHOLDER_STUB}"
STUBS=$(grep -rl "$STUB_MARKER" src/ 2>/dev/null || true)
if [ -n "$STUBS" ]; then
  bad "unremoved stubs:"; printf '%s\n' "$STUBS" | sed 's/^/    /'
else
  ok "no stub left"
fi

# [gate 4] pr-size-guard — 产出体积上限（审查带宽是并行开发的真瓶颈）
# 注意：测的是 BASE_REF...HEAD 分支累计 diff；「单任务」粒度需每任务独立分支或独立 BASE。
step "pr-size-guard"
MAX_DIFF="${MAX_DIFF_LINES:-800}"
if [ "$DIFF_OK" -eq 1 ]; then
  LINES=$(git diff --numstat "$BASE_REF"...HEAD 2>/dev/null | awk '{a+=$1+$2} END{print a+0}')
  if [ -z "$LINES" ] || [ "$LINES" = "0" ]; then
    echo "  [SKIP] 无法取得 diff 行数（无提交或三点语法不适用）"
  elif [ "$LINES" -gt "$MAX_DIFF" ]; then
    bad "diff ${LINES} 行 > 上限 ${MAX_DIFF}：请拆分任务或分两轮交付（MAX_DIFF_LINES 可调）"
  else
    ok "diff ${LINES} 行，在上限内（分支累计口径）"
  fi
else
  echo "  [SKIP] 无有效 diff 基线"
fi

# [gate 5] migration-range — 迁移号段隔离
#    docs/plan/migration-ranges.tsv 格式：<agent><TAB><目录><TAB><起><TAB><止>
step "migration-range"
RANGES="docs/plan/migration-ranges.tsv"
MIG_DIR="${MIGRATIONS_DIR:-migrations}"
# 前缀匹配用 case 而非 grep 正则：MIGRATIONS_DIR 含正则元字符时不会误伤
MIG_CHANGED=$(printf '%s\n' "$CHANGED" | while IFS= read -r f; do case "$f" in "$MIG_DIR/"*) echo "$f";; esac; done)
if [ ! -f "$RANGES" ]; then
  if [ -n "$MIG_CHANGED" ]; then bad "$RANGES 不存在，但有迁移文件改动"; else echo "  [SKIP] 无号段表且无迁移改动"; fi
elif [ -z "$MIG_CHANGED" ]; then
  ok "本轮无迁移文件改动"
else
  BAD_MIG=$(RANGES="$RANGES" MIG_CHANGED="$MIG_CHANGED" node -e '
    const fs = require("fs");
    const rows = fs.readFileSync(process.env.RANGES, "utf8").split("\n")
      .map(l => l.replace(/\r$/, ""))
      .filter(l => l.trim() && !l.trim().startsWith("#"))
      .map(l => l.split("\t")).map(([agent, dir, lo, hi]) => ({ agent, dir, lo: +lo, hi: +hi }));
    const bad = [];
    for (const f of process.env.MIG_CHANGED.split("\n").filter(Boolean)) {
      const num = parseInt((f.split("/").pop() || "").match(/^\d+/)?.[0] ?? "", 10);
      if (Number.isNaN(num)) { bad.push(f + " (文件名无号段前缀)"); continue; }
      const hit = rows.find(r => r.dir && f.startsWith(r.dir) && num >= r.lo && num <= r.hi);
      if (!hit) bad.push(f + " (号段 " + num + " 未落在任何已分配区间)");
    }
    if (bad.length) console.error(bad.join("\n"));
    process.exit(bad.length ? 1 : 0);
  ' 2>&1) || { bad "迁移文件号段越界:"; printf '%s\n' "$BAD_MIG" | sed 's/^/    /'; }
  [ -z "$BAD_MIG" ] && ok "migration ranges OK"
fi

# [gate 6] oasdiff — OpenAPI 破坏性变更检测（需 oasdiff；未安装则跳过）
step "oasdiff"
SPEC="${OPENAPI_SPEC:-openapi.yaml}"
if command -v oasdiff >/dev/null 2>&1 && [ -f "$SPEC" ] && [ "$DIFF_OK" -eq 1 ]; then
  if oasdiff breaking "$BASE_REF:$SPEC" "$SPEC" --fail-on ERR 2>&1 | sed 's/^/    /'; then
    ok "no breaking API change"
  else
    bad "breaking change detected in $SPEC（字段删除/类型收窄/枚举缩水/必填化）"
  fi
else
  echo "  [SKIP] oasdiff 未安装或 $SPEC 不存在 → 建议装上：这是并行期最便宜的契约护栏"
fi

# [gate 8] authz-coverage — 权限注解覆盖（默认严格：缺权限 = FAIL；AUTHZ_STRICT=0 降级 WARN）
step "authz-coverage"
node scripts/authz-coverage.mjs 2>&1 | sed 's/^/    /' || bad "endpoints missing authz"

# [gate 11] duplication-check — 重复度
step "duplication-check"
if [ -f scripts/dup-check.mjs ]; then
  node scripts/dup-check.mjs 2>&1 | sed 's/^/    /' || bad "duplication over threshold"
else
  echo "  [SKIP] scripts/dup-check.mjs 不存在（Integrator 需同步产出「抽象候选清单」）"
fi

# [gate 14/15/19/20/21] tsc / eslint / build / unit / e2e
# 包管理器探测：pnpm 优先，其次 npm/npx，都没有则 SKIP（区分「工具缺失」与「检查失败」）
if command -v pnpm >/dev/null 2>&1; then PM="pnpm"; PMX="pnpm exec"
elif command -v npm >/dev/null 2>&1; then PM="npm"; PMX="npx --no-install"
else PM=""; PMX=""; fi
has_pkg_script() {
  [ -f package.json ] || return 1
  node -e 'const s=require(process.cwd()+"/package.json").scripts||{};process.exit(s[process.argv[1]]?0:1)' "$1" 2>/dev/null
}
no_pm() { echo "  [SKIP] 未检测到 pnpm/npm"; }

step "tsc"
if [ -z "$PM" ]; then no_pm
elif [ -f tsconfig.json ]; then $PMX tsc --noEmit || bad "tsc"
else echo "  [SKIP] 无 tsconfig.json"; fi

step "eslint"
if [ -z "$PM" ]; then no_pm
elif has_pkg_script lint; then "$PM" run lint || bad "eslint"
elif [ -f .eslintrc ] || [ -f .eslintrc.js ] || [ -f .eslintrc.json ] || [ -f eslint.config.js ] || [ -f eslint.config.mjs ]; then $PMX eslint . --max-warnings=0 || bad "eslint"
else echo "  [SKIP] 无 eslint 配置或 lint script"; fi

step "build"
if [ -z "$PM" ]; then no_pm
elif has_pkg_script build; then "$PM" run build || bad "build"
else echo "  [SKIP] package.json 无 build script"; fi

step "unit"
if [ -z "$PM" ]; then no_pm
elif has_pkg_script "test:run"; then "$PM" run "test:run" || bad "unit tests"
elif has_pkg_script test; then "$PM" run test || bad "unit tests"
else echo "  [SKIP] package.json 无 test/test:run script"; fi

step "e2e"
if [ -z "$PM" ]; then no_pm
elif [ -d tests/e2e ] || [ -d e2e ] || [ -f playwright.config.ts ] || [ -f playwright.config.js ]; then
  $PMX playwright test || bad "e2e"
else echo "  [SKIP] 未发现 e2e 目录或 playwright 配置"; fi

printf '\n=================\n'
[ "$FAIL" -eq 0 ] && { echo "GATE PASS — 可以合并"; } || { echo "GATE FAIL — 按归属回派原 Implementer"; }
exit $FAIL
