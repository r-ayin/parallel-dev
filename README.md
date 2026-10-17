# parallel-dev — 多 Agent 并行开发技能（前端 / 全栈）

> An Agent Skill for multi-agent parallel frontend/fullstack development.
> 核心原则：**串行定契约，并行填实现，串行做接线，用可执行门禁代替口头汇报。**

一套给 AI 编码代理用的「施工规范」：一个协调 Agent 带 3~6 个实现 Agent 并行开发一个迭代（5~30 个页面 / 多条 feature 切片），靠目录独占 + 契约冻结 + 23 项机器门禁保证并行不打架、交付不假绿。

源自真实中后台/全栈项目实践；经四路对抗审计（脚本攻击 / 一致性合规 / 事实核查 / 开源 landscape）修复强化，文档中 12 个外部研究引用已逐条溯源核实。

## 安装

```bash
# 方式一：clone 到技能目录（Claude Code / DSH 等支持 Agent Skills 的环境）
git clone https://github.com/r-ayin/parallel-dev ~/.claude/skills/parallel-dev

# 方式二：vercel skills CLI
npx skills add r-ayin/parallel-dev
```

安装后对 Agent 说「并行开发 / 拆成并行任务 / 契约冻结 / 给项目装门禁」即可触发。

## 给项目装门禁（1 分钟）

```bash
bash ~/.claude/skills/parallel-dev/scripts/install-gates.sh /path/to/your-project
cd /path/to/your-project
BASE_REF=main SCAN_ALL=1 bash scripts/guard.sh        # 首次建基线
RUN_AS_AGENT=impl-1 BASE_REF=main bash scripts/guard.sh  # 并行期单任务归属校验
```

## 内容结构

| 路径 | 内容 |
|---|---|
| `SKILL.md` | 执行入口：模式选择（前端/全栈）、阶段表、12 条红线、失效信号 |
| `references/frontend.md` | 前端六阶段方案 + 热点文件 A/B/C 策略 + 反模式清单 |
| `references/fullstack.md` | 全栈方案：Stage A demo 比稿 / Stage B 交互分析 / 三重契约 / 23 项门禁 / 公开研究引用 |
| `references/templates.md` | 模板 A~F：OWNERSHIP 矩阵 / 任务书 / 契约变更申请 / 集成记录 / 契约版本 / 派发循环 |
| `references/templates-stageab.md` | 模板 G~M：demo 任务书 / 外部走查 / 交互分析 / 全栈切片 / 决策日志 / 抽象候选 / 反馈分类 |
| `references/ecosystem.md` | 开源同类项目调研与吸收清单（含核实深度分级） |
| `scripts/` | guard.sh（门禁主链）· dedup.mjs（语义去重）· dup-check.mjs（重复度/硬编码样式）· authz-coverage.mjs（权限覆盖）· install-gates.sh |

## 致谢（机制来源，详见 references/ecosystem.md）

- [contractor](https://github.com/FelipeCostaBR/contractor) — 两轮熔断、verdict 落盘、防缓存假绿、verifiedBy
- [adhd](https://github.com/UditAkhourii/adhd) — 认知框架畸变比稿、三轴打分、pre-flight 成本闸门
- [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) — 机器可读 terminal status 与 resume 路由
- [aidlc-workflows](https://github.com/awslabs/aidlc-workflows) — 多镜头 LLM 语义评审层
- [spec-kit](https://github.com/github/spec-kit) — SYNC IMPACT REPORT、converge 收敛判定
- [claude-squad](https://github.com/smtg-ai/claude-squad) — git worktree per agent 硬隔离

## License

MIT
