# 开源同类项目 landscape 与吸收清单

> 核实日期：2026-10-16。核实深度分级：
> **★★★** = 主会话直接拉取原文逐条验证；**★★** = 调研子代理拉取机制文档原文、主会话抽查关键句复核；**★** = 仅 README / 文件树级证据。
> 纪律：只有 ★★★/★★ 的机制允许合并进方法论正文；★ 级只在本文件挂链接 + 一句话理念，不抄内容。
> 全部 star 数来自 api.github.com 单一来源（调研当时值），量级参考、非精确承诺。

## 一、已合并（机制进了正文）

| 项目 | star / license | 深度 | 吸收的机制 | 落点 |
|---|---|---|---|---|
| [FelipeCostaBR/contractor](https://github.com/FelipeCostaBR/contractor) | 4 / MIT | ★★★（invariants.md + protocol.md） | 两轮熔断 + stuck 分支固化 + halted；轮次计数器与日志一致性自检；verdict 原始落盘、缺失 = fail；集成 gate 先清缓存防假绿；verifiedBy 命令 + 退出码重跑；handoff 落盘 + ≤1KB digest 回传；seats 边界（orchestrator 不写 feature 代码 / validator 只读对抗） | fullstack.md §8.5；SKILL.md 红线 9-12 |
| [UditAkhourii/adhd](https://github.com/UditAkhourii/adhd) | 4.4k / MIT | ★★★（skills/adhd/SKILL.md） | 比稿认知框架畸变（regulator/biology/speedrunner/10-year-old/$0 budget）；发散/评审两相硬分离；novelty/viability/fit 三轴打分 + trap 标记；pre-flight 三问成本闸门；「分支互相看见即互相锚定」 | templates-stageab.md 模板 G |
| [bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) | 54k / README 徽章 MIT + TRADEMARK.md | ★★★（docs/build/autonomous-development-loops.md） | 交付报告机器可读 terminal status + resume 路由表；checkpoint 人审字段化（归 orchestrator，worker 永不读写）；worker 永不自己挑下一任务 | templates.md 模板 B/D/F |
| [awslabs/aidlc-workflows](https://github.com/awslabs/aidlc-workflows)（AI-DLC） | 5.3k / MIT-0 | ★★★（.github/prompts/ai-pr-review-judge.md） | 多镜头 LLM 语义评审制度化：scope/security/UX 镜头 + judge schema 判卷 + 评审台账 | fullstack.md §8.6 |
| [github/spec-kit](https://github.com/github/spec-kit) | 141k / MIT | ★★★（.specify/memory/constitution.md） | 契约升版附 SYNC IMPACT REPORT（下游工件逐条核查）；converge 三态收敛判定（converged/progressing/stalled） | templates.md 模板 E；SKILL.md 阶段表 |

## 二、仅链接 + 理念（★ 级证据，不抄内容）

| 项目 | star / license | 理念 | 引用处 |
|---|---|---|---|
| [smtg-ai/claude-squad](https://github.com/smtg-ai/claude-squad) | 8.6k / AGPL-3.0 | git worktree per agent = 比目录独占更硬的物理隔离；orca（93k）/emdash（6k，YC W26）/superset（15k）三大 ADE 同做法佐证行业收敛 | SKILL.md 红线 3；fullstack.md §6.5 |
| [eyaltoledano/claude-task-master](https://github.com/eyaltoledano/claude-task-master) | 28k / MIT+Commons Clause（禁商用），已停滞约 6 个月 | 派发前任务粒度/复杂度自检（.kiro/hooks/tm-complexity-analyzer）——只吸理念，不抄任何原文 | SKILL.md Phase 3 粒度自检 |
| [Chorus-AIDLC/Chorus](https://github.com/Chorus-AIDLC/Chorus) | 1.2k / AGPL-3.0 | 阶段动作权限标注（idea:write / task:write / *:admin），与目录独占互补 | templates.md 模板 A 注 |
| [gemini-cli-extensions/conductor](https://github.com/gemini-cli-extensions/conductor) | 3.8k / Apache-2.0 | 失败 track 的正式 revert 流程 + ownership 释放；与闭源 conductor.build 同名不同物 | fullstack.md Phase 4 第 12 条 |
| [buildermethods/agent-os](https://github.com/buildermethods/agent-os) | 5.5k / MIT（内容薄，拒外部 PR） | discover-standards：brownfield 先从既有代码提取现行惯例再定契约 | SKILL.md 何时使用 |

## 三、生态对照（核实后判定不合并）

| 项目 | star | 判定理由 |
|---|---|---|
| ruvnet/ruflo（原 claude-flow，已改名） | 75k | swarm/hive-mind 运行时框架，70+ 协调器技能，概念繁杂营销密度高，非方法论 |
| FoundationAgents/MetaGPT | 70k | SOP 角色分工研究框架，停滞约 9 个月 |
| OpenBMB/ChatDev | 34k | ChatChain 阶段瀑布，研究框架 |
| OpenHands/OpenHands | 91k | agent 运行时/沙箱，非协作方法论 |
| BloopAI/vibe-kanban | 28k | README 首屏宣布 sunsetting；「planning/review 是瓶颈」理念与本技能一致，无机制可吸收 |
| stablyai/orca · superset-sh/superset（license 非标准） · generalaction/emdash | 93k/15k/6k | 桌面 ADE 产品层；emdash 仓内 .scratch/<build>/issues/NN-*.md 编号 issue 树可作「任务书文件化」旁证 |
| 小项目备查 | — | tempest(190) / code-conductor(113) / specs.md(219) / tyran(82) / writ(16，contract-first 同族) / ai-code-conductor(58)，均未深查 |

## 四、调研死路记录（防重复踩）

- conductor-build/conductor → 404（闭源云产品）；conductor-oss/conductor 是 Netflix 工作流引擎（无关）
- AgentOrchestra → 主体是 arXiv 2506.12508 论文，GitHub 仅 ≤4★ 碎片仓
- agentic-labs/ai-dlc、github/ai-dlc → 404，真身是 awslabs/aidlc-workflows
- ruvnet/claude-flow 按旧名搜索会漏（API 重定向到 ruflo）
- GitHub API unauthenticated 60 req/h；抓机制文档正文走 raw.githubusercontent.com 不限流
