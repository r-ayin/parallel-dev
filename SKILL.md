---
name: parallel-dev
description: 前端/全栈项目的多 Agent 并行开发方法论与可执行门禁：串行定契约、并行填实现、串行接线、用 gate 代替口头汇报。覆盖页面 demo 比稿、交互分析、三重契约冻结、纵向 feature 切片、OWNERSHIP 目录独占、语义去重、migration 号段、authz 覆盖、重复度检查。当用户提到 并行开发、多agent开发、fan-out、契约冻结、任务书、OWNERSHIP、门禁guard、前端并行方案、全栈并行方案、中后台多页面并行开发、demo比稿、交互分析、拆分并行任务 时使用。不覆盖：长期驻留领域专家团（用 guild）、单项目下一步单步路由（用 autonomous-studio）。
metadata:
  version: "1.2.0"
  created: "2026-10-16"
---

# parallel-dev — 多 Agent 并行开发（前端 / 全栈）

> 核心原则：**串行定契约，并行填实现，串行做接线，用可执行门禁代替口头汇报。**
> 准入判据（第一性）：**可以并行的，只有「所有会影响他人的决定都已被规定」的部分。**

## 何时使用

- 一个迭代要产出 5～30 个页面 / 多条 feature 切片，计划用多个 subagent 并行实现
- 用户要求「拆成并行任务」「多 agent 开发」「fan-out 实现」
- 需要在项目里建立并行开发门禁（contract-guard / ownership-guard / dedup / authz 等）
- **既有项目**（brownfield）并行改造：Phase 1 定 tokens/请求层前，先从现有代码提取现行惯例成文（agent-os discover-standards 思路），契约跟随现状而非凭空另设

**何时不用**：单人单任务的小改动；产出无法通过目录独占隔离的工作。多 agent 约消耗 15× 于普通对话的 token——任务价值必须盖得过这份开销。

## 先做一道题：产出最后怎么合并？

| 合并方式 | 决定需互相一致？ | 并行度 | 典型场景 |
|---|---|---|---|
| 选择式（选一个扔其余） | 不需要 | 8～20 | demo 比稿、方案探索 |
| 汇总式（只读同一份，各出报告） | 不需要 | 4～8 | 交互扫描、安全/可达性走查 |
| 缝合式（拼成一个可运行系统） | **强需要** | 3～6 | 并行实现（Phase 3） |

并行度上不去，几乎总是因为在缝合式任务上按比稿式直觉开 agent。**先问怎么合，再定开几个。**

## 模式选择

| 场景 | 主文档 | 模板包 |
|---|---|---|
| 纯前端（React/Vue 中后台、单体或 monorepo） | references/frontend.md | references/templates.md（A~F） |
| 全栈（DB→API→UI 打穿） | references/fullstack.md | references/templates.md + references/templates-stageab.md（G~M） |

两份文档均含完整阶段定义、进入/退出条件、反模式清单。全栈版额外覆盖：Stage A demo 比稿、Stage B 交互分析、三重契约（数据→API→交互，顺序不可颠倒）、migration 号段、鉴权、可观测性、发布验证。

## 执行流程（两种模式共用的骨架）

| 阶段 | 并行性 | 关键产出 | 退出条件 |
|---|---|---|---|
| 0 结构化需求 | 串行 | 页面树 / 接口清单 / OWNERSHIP 初稿 | 每页面能答「读什么接口、写什么状态、跳去哪」 |
| 1 基座骨架 | 串行一次 | tokens / 请求层 / 鉴权 / store 注册表 / 路由 stub / CI | **绿色基线**：gate 全绿，stub 可访问 |
| 2 契约冻结 | 串行 | contracts/** + 可运行 mock + 数据语义约定 | Implementer 不看后端文档能独立开工跑通 mock |
| 3 并行实现 | 缝合式 3~6 | 各切片目录 + 单测 + 交付报告（首行机器可读 status） | 各任务 gate 绿；派发前必答「还有影响他人的未定决定吗」；粒度自检：预估产出 >800 行或跨 >2 模块 → 再拆（task-master complexity-analysis 思路） |
| 4 集成 | 串行 1 人 | 接线 / 语义去重 / 清 stub / 抽象候选清单 / integration-notes | 不接受自述完成，全部交 Phase 5 验证 |
| 5 门禁 | 自动化 | `pnpm gate` 全绿 log | 唯一可信的正确性证据 |
| 6 发布验证（全栈） | 串行 | flag 灰度 / 回滚演练 / trace 贯穿抽查 | 迁移必须演练 down |
| 7 定向回派 | 循环 5→7→5 | 回派记录（门禁编号+报错原文+文件路径） | 连续两轮同任务失败 → 熔断：固化 stuck 分支 + halted 交人，或退回 Phase 2 重判契约 |

全栈模式在 Phase 0 之前还有 Stage A（demo 比稿，选择式高并行）与 Stage B（交互分析，汇总式并行），见 references/fullstack.md §4/§5。全栈模式的 Phase 0 定义与前端版一致（fullstack.md §7 开头有指引）。

> 编号对照：纯前端模式的「定向修补」为 Phase 6（frontend.md），全栈模式为 Phase 7；门禁编号统一以 fullstack.md §8 为准（guard.sh 注释同口径）。每轮 gate 循环产出三态 converge 判定（spec-kit）：converged（全绿且无新 CR）/ progressing（全绿但有新 CR 或新任务）/ stalled（熔断交人）。

## 在本环境（DSH）的落地方式

- **Coordinator / Contract Owner / Integrator = 主会话**（拥有全仓写权限，负责拆任务、裁决、接线）
- **理需求（Phase 0 / Stage A 收敛 / 契约拍板）一律苏格拉底式聊天**：交互式对话逐步深入，一次只问一个问题，基于用户回答追问下一层；可以在聊天文字里给出建议方向供参考，但**禁止用选项卡片/按钮组让用户点选**（用户明确偏好，2026-10-17）
- **Implementer = subagent**：同一轮派发的多个独立 subagent 放在一条消息里同时启动；大规模扇出（Stage A 比稿、Stage B 六维扫描）用 workflow 工具编排
- **任务书 = subagent prompt**：必须包含 references/templates.md 模板 B 的八节（目标/非目标/只读契约/允许写入路径/依赖 mock/必须复用/可执行验收/交付格式），并对齐本仓 AGENTS.md 的子代理委派七要素（环境约束、精确目标、输出 schema、只读边界、STATUS 闭环、文件:行号锚点、死路清单）；交付报告首行机器可读 status（done/blocked/halted/needs_contract_change），Coordinator 按字段机械路由（BMAD resume 表思路）
- **Reviewer = gate 脚本 + 主会话**：不信任任何 agent 的「已完成」自述，只认 `bash scripts/guard.sh` 退出码；verdict 原始落盘、缺失即 fail（红线 10）；语义级评审层见 fullstack.md §8.6
- **契约变更**：Implementer 只能提 CONTRACT_REQUEST（模板 C），主会话裁决后升版本号并广播（模板 E）
- **跨 agent 决定传递**：decisions.log（模板 K）随任务书一起派发——这是并行 agent「看到彼此决定」的唯一工程化办法

## 门禁安装与使用

把 scripts/ 下 4 个门禁脚本装进目标项目（幂等，不覆盖已有文件）：

```bash
bash <技能目录>/scripts/install-gates.sh <项目根目录>
```

装完后在项目里：

```bash
# 首次建基线（全仓扫描；authz 默认严格：缺权限 = FAIL）
BASE_REF=main SCAN_ALL=1 bash scripts/guard.sh
# 日常（对 main 的 diff 范围检查），或 pnpm gate
BASE_REF=main bash scripts/guard.sh
# 并行期：每个任务提交前按自己的归属校验（防 A 改 B 目录——并集模式查不出归属）
RUN_AS_AGENT=impl-1 BASE_REF=main bash scripts/guard.sh
# 仅调试期放宽 authz：AUTHZ_STRICT=0
```

脚本与门禁项对应（完整 23 项清单见 references/fullstack.md §8）：

| 脚本 | 覆盖 | 已知局限 |
|---|---|---|
| guard.sh | contract（含治理文件自保护、rename -M 检测）/ownership（重叠校验 + RUN_AS_AGENT 归属模式）/deps/pr-size/migration-range/oasdiff/stub/route-snapshot + 按能力调度 tsc/eslint/build/unit/e2e | 无效 BASE_REF = 显式 FAIL 不静默；oasdiff 需外部安装；route-snapshot 需自建 gen-routes.mjs |
| dedup.mjs | 路由 path 重复（模板动态段归一、JSX 表达式容器可见）、动态段吞静态段、barrel 同名导出（export* 告警）、slice 撞名（递归子目录）、埋点 key | 正则识别非 AST；变量间接不可见；非路由语境 path 重复降级 WARN |
| dup-check.mjs | 硬编码色值（阻断；块注释/CSS 选择器/测试目录不误报）、svg 属性色与魔法像素（告警）、跨文件重复块（接 jscpd，数组传参防注入） | 相似度检测交给 jscpd，不自研 |
| authz-coverage.mjs | Express/Koa/NestJS/Gin/FastAPI endpoint 权限覆盖；默认严格；注释剥离（TODO/isPublic 注释不算声明）、多行声明与同行多路由可见、文件级中间件识别、同行路由不串味 | 正则识别非 AST，冷门写法靠语义评审层补（fullstack.md §8.6） |

## 硬性规则（红线）

1. **纵向切，不横向切**：一个 agent 同时负责它切片的 migration→API→页面→测试。「一个写所有后端、一个写所有前端」= 隔着未定接口互猜，是头号反模式
2. **横切层禁止并行**：design tokens、请求层、鉴权、中间件链、全局 store 索引、构建配置——下游是所有人，天然串行
3. **目录独占两两不重叠**：重叠就不是并行，是竞态。写入范围登记在 docs/plan/ownership.tsv，gate 校验重叠与归属（并行期每任务用 `RUN_AS_AGENT=<id>` 校验单 agent 归属）。硬隔离升级路径：**git worktree per agent**（claude-squad / orca / emdash 行业做法），误写他人目录在文件系统层不可能
4. **禁止写入清单必须配变更回报通道**：只堵不疏，agent 会造局部 hack。「不许改 contracts」+「不够用提 CONTRACT_REQUEST」缺一不可
5. **并行期锁死依赖**：package.json / lockfile 无人可写，gate 用 git diff 卡
6. **只认 gate，不认自述**：任何「已完成」都要终态验证（构建/测试/去重全绿），过程不验证
7. **demo 三不沉**：prototype/** 不进主干、demo 依赖不进 lockfile、硬编码假数据不进 fixtures
8. **抽取是横切动作**：只在 Phase 4 串行做；并行期发现重复只登记「抽象候选清单」，不就地重构
9. **两轮熔断 + 现场固化**：同一任务连续两轮 gate 失败即停回派，现场固化到 `debug/<任务>-stuck` 分支、交付报告标 `status: halted` 交人；轮次计数器必须与回派日志条数一致，计数器落后 = 门禁自身报错（contractor invariants）
10. **验证产物原始落盘**：gate 逐项 verdict/退出码先落盘 `.gate/verdict-<round>.json` 再派生结论；**缺失 verdict 文件 = FAIL，绝不假定 pass**
11. **集成 gate 先清缓存**：增量构建缓存会造假绿；集成测试范围从 commit 全集派生，不按 touched-area
12. **交付落盘 + digest 回传 + verifiedBy**：完整报告写 `docs/handoff/<任务>.md`，只回 Coordinator ≤1KB 摘要；每个「已完成」附确切命令 + 退出码，复核重跑命令不重读散文

## 最小起步（不要一次上全套）

第一批只做七件，已覆盖大部分收益：
1. Stage A/B 任务书 + **假设清单**要求（杠杆最大成本最低；AI 会替你做几十个无声决定：分页大小/排序默认/空值显示/时区/金额单位）
2. Phase 1 绿色基线（tokens + 请求层 + 鉴权 + store 注册表）
3. Phase 2 契约冻结 + 禁止写入清单 + 变更回报通道
4. 纵向切片 + 目录独占任务书
5. gate 四项：contract-guard / ownership-guard / tsc / dedup-check
6. 全栈加三项：authz-coverage / oasdiff / duplication-check（成本极低收益极高）
7. 只看交付后指标（变更失败率、回滚次数），不看过程量（提交数、PR 数）

路由生成器（B 策略）、barrel 自动生成、迁移号段强校验——页面数超过 8~10 或痛点出现再上。

## 失效信号（何时停止/降级并行）

| 信号 | 判读 | 动作 |
|---|---|---|
| gate 失败 >30% 与契约/集成相关 | 契约没冻住 | 停并行回 Phase 2 |
| 单任务平均耗时 <20 分钟 | 拆太细 | 合并任务 |
| 回派文件 70% 集中在少数几个 | 隐藏热点文件 | 该文件改 A（一次写全）或 B（约定式） |
| 同一门禁项多任务反复失败 | 基建问题 | 交 Phase 1 owner 修，别继续回派 Implementer |
| demo 轮次 >5 | 需求方没想清楚 | 停止迭代，这是流程问题 |
| 变更失败率/回滚次数上升 | 吞吐与不稳定性同涨 | 收紧门禁、降并行度 |

串并配比 3:7 / 4:6、2~4 轮收敛、3~6 并行度均为经验启发式，无公开数据支撑——按上表信号调整，不按数字坚持。

## 常见错误

- **按层拆任务**（前端组/后端组/测试组）→ 跨层耦合把并行变回串行。按业务纵向切
- **跳过 Phase 1 直接并行** → 花一半时间在集成期擦屁股。骨架质量决定一切
- **用 C 策略（追加+集成去重）管注册表** → 文本合并干净 ≠ 语义合并正确，同 path 双路由「成功合并」实为静默覆盖。注册表用 A/B，C 只管清单类（埋点 key、i18n）
- **回派时开新 agent** → 上下文在原 Implementer 那儿。回派消息只带三样：门禁编号 + 报错原文 + 文件路径
- **依赖 agent 自述完成** → METR RCT 实测：资深开发者用 AI 慢 19% 但自认为快 20%。终态门禁是唯一证据
- **共享 seed 文件/共享测试库** → 互相污染，只在 CI 复现的随机失败。各 agent 独立 builder
- **鉴权「最后统一处理」** → 它是所有 endpoint 的上游，必须 Phase 1 落地，gate 用 authz-coverage 强制

## 参考资料

- references/frontend.md — 前端并行开发方案（角色/拆分级别/热点文件 A-B-C 策略/六阶段/gate 12 项/反模式）
- references/fullstack.md — 全栈完整方案（理论边界/合并成本三档/Stage A/B/三重契约/分配矩阵/gate 23 项/成本带宽数据/实例走查/失效信号，附公开研究来源）
- references/templates.md — 模板 A~F：OWNERSHIP 矩阵 / 任务书 / CONTRACT_REQUEST / 集成记录 / 契约版本 / Coordinator 派发循环
- references/templates-stageab.md — 模板 G~M：demo 任务书 / 外部走查记录 / 交互分析任务书 / 全栈切片任务书 / 决策日志 / 抽象候选清单 / 走查反馈分类口径
- references/ecosystem.md — 开源同类项目 landscape：逐项核实（含深度分级 ★）与吸收清单、生态对照
- scripts/ — guard.sh（门禁主链）、dedup.mjs、dup-check.mjs、authz-coverage.mjs、install-gates.sh（装入项目）
