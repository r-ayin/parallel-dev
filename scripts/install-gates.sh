#!/usr/bin/env bash
# install-gates.sh — 把 parallel-dev 技能的门禁脚本安装进目标项目
# 用法: install-gates.sh [项目根目录]   （缺省 = 当前目录）
# 做四件事:
#   1. 复制 4 个门禁脚本到 <项目>/scripts/
#   2. 创建治理文件骨架（docs/plan/ownership.tsv、migration-ranges.tsv、contract-version.md、
#      decisions.log 与 docs/integration-notes.md —— 路径与 templates.md/dedup.mjs 口径一致）
#   3. 若存在 package.json 且 scripts 里无 "gate"，追加 "gate": "bash scripts/guard.sh"
#      （按 JSON 解析判断，不受 dependencies 里同名包干扰；JSON 损坏时告警并继续，不中途死掉）
#   4. 打印下一步指引
# 幂等：已存在的文件一律不覆盖。
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-$(pwd)}"
if ! PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd)"; then
  echo "目标目录不存在: $PROJECT" >&2; exit 1
fi
if [ "$PROJECT" = "$SKILL_DIR" ] || [[ "$PROJECT" == */skills/parallel-dev ]]; then
  echo "拒绝：目标目录是技能自身（$PROJECT）。请传入你的项目根目录。" >&2
  exit 1
fi

echo "→ 安装门禁到: $PROJECT"
mkdir -p "$PROJECT/scripts" "$PROJECT/docs/plan"

for f in guard.sh dedup.mjs dup-check.mjs authz-coverage.mjs; do
  if [ -f "$PROJECT/scripts/$f" ]; then
    echo "  [skip] scripts/$f 已存在"
  else
    cp "$SKILL_DIR/$f" "$PROJECT/scripts/$f"
    echo "  [new]  scripts/$f"
  fi
done
chmod +x "$PROJECT/scripts/guard.sh"

# 治理文件骨架（幂等）
if [ ! -f "$PROJECT/docs/plan/ownership.tsv" ]; then
  printf '# agent-id\tglob（两两不重叠是并行的前提；gate 会校验重叠）\n# coord\tsrc/app/**\n# impl-1\tsrc/modules/<module>/pages/<page>/**\n' > "$PROJECT/docs/plan/ownership.tsv"
  echo "  [new]  docs/plan/ownership.tsv（模板，需填写）"
fi
if [ ! -f "$PROJECT/docs/plan/migration-ranges.tsv" ]; then
  printf '# agent\t目录\t起\t止\n# f2\tmigrations/\t100\t199\n' > "$PROJECT/docs/plan/migration-ranges.tsv"
  echo "  [new]  docs/plan/migration-ranges.tsv（模板，需填写）"
fi
for f in contract-version.md decisions.log; do
  if [ ! -f "$PROJECT/docs/plan/$f" ]; then
    : > "$PROJECT/docs/plan/$f"
    echo "  [new]  docs/plan/$f"
  fi
done
if [ ! -f "$PROJECT/docs/integration-notes.md" ]; then
  : > "$PROJECT/docs/integration-notes.md"
  echo "  [new]  docs/integration-notes.md"
fi

# package.json gate script（JSON 解析三态：has / missing / badjson）
if [ -f "$PROJECT/package.json" ] && command -v node >/dev/null 2>&1; then
  GATE_STATE=$(node -e '
    const fs = require("fs");
    let j;
    try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
    catch (e) { console.log("badjson"); process.exit(0); }
    const s = (j && j.scripts) || {};
    console.log(s.gate ? "has" : "missing");
  ' "$PROJECT/package.json" 2>/dev/null) || GATE_STATE=badjson
  case "$GATE_STATE" in
    has)     echo "  [skip] package.json 已有 scripts.gate" ;;
    missing)
      node -e '
        const fs = require("fs");
        const p = process.argv[1];
        const j = JSON.parse(fs.readFileSync(p, "utf8"));
        j.scripts = j.scripts || {};
        j.scripts.gate = "bash scripts/guard.sh";
        fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
      ' "$PROJECT/package.json"
      echo "  [edit] package.json 追加 scripts.gate = bash scripts/guard.sh" ;;
    *) echo '  [WARN] package.json 解析失败（JSON 损坏？）——脚本已装，但 scripts.gate 未注入，请手工添加 "gate": "bash scripts/guard.sh"' ;;
  esac
elif [ -f "$PROJECT/package.json" ]; then
  echo "  [WARN] 未找到 node，跳过 package.json gate 注入"
fi

cat <<'EOF'

安装完成。下一步（按《SKILL.md》§执行流程）：
  1. 填写 docs/plan/ownership.tsv（每个并行任务的独占目录；glob 两两不重叠，gate 会校验）
  2. 首次建基线：BASE_REF=main SCAN_ALL=1 bash scripts/guard.sh   （authz 默认严格）
  3. 并行期每个任务提交前：RUN_AS_AGENT=<agent-id> BASE_REF=main bash scripts/guard.sh
  4. 单项调试直接跑脚本：node scripts/dedup.mjs / node scripts/dup-check.mjs /
     SCAN_ALL=1 node scripts/authz-coverage.mjs   （guard.sh 始终全链，不接受单项参数）
  5. 可选依赖：pnpm add -D jscpd（重复块检测）；oasdiff（OpenAPI 破坏性变更）
EOF
exit 0
