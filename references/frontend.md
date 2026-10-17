# 前端多 Agent 并行开发方案

> 适用：中后台 / Web 应用，React 或 Vue，单体或 monorepo，由 1 个协调 Agent + N 个实现 Agent 并行完成一个迭代（5～30 个页面）的场景。
> 核心原则：**串行定契约，并行填实现，串行做接线，用可执行门禁代替口头汇报。**

---

## 0. 全局约定

### 0.1 角色

| 角色 | 数量 | 职责 | 权限 |
|---|---|---|---|
| Coordinator（协调） | 1 | 拆任务、发契约、判定完成 | 全仓读写 |
| Contract Owner（契约） | 1（可与 Coordinator 同人） | 唯一可改 `contracts/` | 仅 `contracts/**` |
| Implementer（实现） | 3～6 | 只写自己拥有的目录 | 仅 OWNERSHIP 中列出的路径 |
| Integrator（集成） | 1 | Phase 4 接线、去重、清 stub | `src/app/**`、`src/store/index.ts`、barrel |
| Reviewer（门禁） | 自动化 + 1 | 跑 gate、视觉走查、判定回派 | 只读，产出报告 |

### 0.2 并行度

- 起始 **3 个** Implementer，每轮验证 gate 通过后再加。
- 上限 **6 个**（经验起点值；判据见全栈版 §2——上限由「还有哪些决定没被规定」决定，不由任务数决定）。超过 6，Phase 4 的集成时间会吃掉并行省下的时间（协调成本近似平方增长）。
- 判定依据不是"能开几个 agent"，而是"**互不重叠的目录有几个**"。重叠就不是并行，是竞态。

### 0.3 拆分级别（落到哪一层并行）

| 级别 | 单元 | 是否作为并行任务 | 说明 |
|---|---|---|---|
| L0 | monorepo package / 微前端子应用 | 是 | 构建产物级隔离 |
| **L1** | **业务模块**（订单/用户/报表） | **主力** | 纵向自带完整链路 |
| **L2** | **页面 / 路由** | **主力** | 一个 agent 一个页面，200～800 行 |
| L3 | 组件（叶子、纯展示） | 不单独派 | 作为 L2 的附带产出 |
| L4 | hook / util / 类型 | 不单独派 | 属于 L2、L3 附带 |
| 横切 | 设计系统、请求层、全局 store | **禁止并行** | 下游是所有人，天然串行 |

**按业务纵向切，不按层横向切。** 一个 agent 必须同时负责它的 API 调用、组件、状态、测试。

---

## 1. 文件类型分派表（热点文件治理，方案主体）

这是整套方案最关键的一张表。不同注册表用不同策略，不要全项目统一。

| 文件类型 | 策略 | 阶段 | 写入权限 | 校验方式 |
|---|---|---|---|---|
| 路由表 `src/app/routes.tsx` | **B 约定式**（页面数 >8 且结构规整）/ **A 一次写全**（需要精细 meta、权限、重定向） | Phase 1 定稿 | Phase 3 只读 | 生成清单快照 diff |
| 页面级 meta / 权限 | A | Phase 1 | 只读 | `tsc` + snapshot |
| `src/store/index.ts` | **A** | Phase 1 | 只读，slice 名与 state 类型定死 | `tsc` |
| slice 实现 `src/store/slices/<x>.ts` | 各自独占 | Phase 3 | Implementer 独占 | 单测 |
| `src/theme/*`、design tokens | **A，最严格** | Phase 1 | 只读，任何人不得改 | 值级 snapshot |
| 请求层 `src/api/client.ts`、拦截器 | A | Phase 1 | 只读 | 单测 |
| barrel `components/index.ts` | **B 自动导出** 或 Phase 3 一律用深路径 import，Phase 4 再生成 | Phase 4 | Integrator | 去重校验 |
| API 类型 / DTO `src/contracts/api/**` | A | Phase 2 冻结 | 只读 | `tsc` + 契约测试 |
| 埋点 key 清单 | **C 追加 + 去重** | Phase 3 | 各自追加 | 语义去重脚本 |
| i18n 文案 | **C** | Phase 3 | 各自追加 namespace | key 冲突校验 |
| 图标 / 组件库使用清单 | C | Phase 3 | 只读组件库 | 无 |
| `package.json` / lockfile | **A，Phase 3 期间完全禁止** | Phase 1 | 无人可写 | gate 检查 git diff |
| `tsconfig.json` / 构建配置 | A | Phase 1 | 无人可写 | — |

规则总结：
- **注册表（会导致行为错误的）→ A 或 B**
- **清单（多一条少一条不会坏的）→ C**

### 1.1 选 A 还是选 B 的判定顺序

1. 这份清单能在开工前穷举吗？→ 能，用 **A**。
2. 结构能完全由文件名/路径表达吗？有成熟框架支持吗？→ 是，用 **B**（可扩展性最好，能推到 8+ 并行）。
3. 都不行 → 用 **C**，但必须在门禁里补语义去重 + 关键路径 e2e。

### 1.2 用 B 时必须补的三件事（否则一定翻车）

1. **命名 lint 规则**：文件名成为公共 API，`detail.tsx` / `details.tsx` / `Detail.tsx` 混用不会报错，只会让页面静默不存在。
2. **生成清单快照 + diff**：Phase 3 结束导出实际路由清单，与 Phase 1 的规划表比对，防止假绿。
3. **显式逃生通道**：别名、重定向、权限屏蔽这类特例集中写在一个 `routes.overrides.ts`，特例超过 10 条就退回 A。

### 1.3 用 A 时必须补的一件事

Phase 1 建 **占位 stub**（每个规划中的页面先建空组件），保证基线构建是绿的。Phase 4 由 Integrator 清理所有残留 stub，并在 gate 里加"stub 计数归零"检查。

---

## 2. 六个阶段（含进入/退出条件）

### Phase 0 — 结构化需求（串行）

**产出**
- 页面树（模块 → 页面 → 页面内区块）
- 数据流图（哪个页面读哪个接口、写哪个 store slice）
- 接口清单（path / method / req / res / 错误码）
- **OWNERSHIP 矩阵初稿**（页面 → 负责人 → 写入路径）

**退出条件**：每个页面都能回答"它读什么接口、写什么状态、跳转去哪"。答不出来的页面退回需求阶段，不要带进并行。

---

### Phase 1 — 骨架（串行，只做一次，不可并行）

内容清单：
1. 目录结构 + 路径别名（`@/`）
2. 构建配置、`tsconfig.json`（`strict: true`）
3. 依赖与 lockfile **一次性装齐**，之后禁止新增
4. design tokens：色板、间距阶梯、字号阶梯、圆角、阴影、断点
5. 基础组件最小集：Button / Input / Select / Table / Modal / Form 壳 / Card / Skeleton
6. 请求层：client、拦截器、错误码映射、loading/401 处理、重试策略
7. store 骨架：slice 注册表、根 state 类型
8. 路由骨架 + 约定式生成器（或一次写全的路由表）+ stub 页面
9. lint / format / commit 规范 / gate 脚本
10. mock 服务（MSW）接线与 handler 注册机制

**退出条件 = 绿色基线**：`pnpm gate` 全绿，页面能访问（内容是 stub）。

> 这一步的质量决定后面所有并行任务的一致性。骨架差，Phase 4 全量返工。宁可在这里多花时间。

---

### Phase 2 — 契约冻结（串行，最关键）

冻结并标记只读的内容：
- `src/contracts/domain/**`：领域实体 TS 类型
- `src/contracts/api/**`：接口 DTO、请求参数、响应结构、错误码枚举
- `src/contracts/routes.ts`：路由 name、path、params、query
- `src/contracts/events.ts`：跨组件事件名、埋点 key、i18n namespace
- `src/contracts/store.ts`：slice 名、state 字段、action 签名
- `src/contracts/components/**`：被多页面共用的组件 props / emits 接口
- `mock/handlers/**` + `mock/fixtures/**`：可运行的假数据

冻结后的纪律（三条，缺一不可）：
1. 这些路径进入 **禁止写入清单**（gate 里用 `git diff` 校验）。
2. 提供 **变更回报通道**：agent 发现契约不够用时，只能提交 `CONTRACT_REQUEST` 给 Contract Owner，不允许自己绕过或另造一套。
3. Contract Owner 改完后 **广播新版本号**，所有受影响任务重新分发。

> 只给第 1 条不给第 2 条是最常见的失败：agent 被堵住但需求真实存在，它会造局部 hack，产生不一致实现。

**退出条件**：Implementer 不看后端文档也能独立开工，跑通 mock 拿到数据。

---

### Phase 3 — 并行 fan-out

派发规则：
- 每个任务 **独占目录**，写入范围两两不重叠（gate 校验）。
- 任务规模：**一个页面一个任务**（含它的私有子组件、数据请求、类型使用、单测）。
- 一个 Implementer 同时只跑一个任务，完成再取下一个。
- 每个任务必须自带可执行验收标准。

任务书模板（八节：六项核心 + 必须复用 + 交付格式，少一项就会出现"它自己发明了一套接口"；完整模板见 templates.md 模板 B）：

```markdown
## T-<模块>-<页面> <页面名>
**目标**：<一句话，用户能做什么>
**非目标**：<明确不做什么，防止顺手扩展>
**契约（只读，禁止修改）**：
- src/contracts/api/<module>.ts
- src/contracts/routes.ts（route name: <x>）
- src/contracts/store.ts（slice: <x>）
**允许写入路径**：
- src/modules/<module>/pages/<page>/**
**依赖 mock**：mock/handlers/<module>.ts（GET /api/<x>）
**验收标准（必须可执行）**：
- pnpm tsc --noEmit 通过
- pnpm vitest run src/modules/<module>/pages/<page> 全绿（≥3 用例：渲染/空态/错误态）
- pnpm exec playwright test tests/e2e/<page>.spec.ts 通过
**交付格式**：改动文件列表 + 未尽事项 + 风险 + 是否需要契约变更
```

并行期间禁止事项（写进每个任务书）：
- 禁止修改 `contracts/`、`theme/`、`api/client.ts`、`store/index.ts`、路由表、`package.json`
- 禁止新增依赖
- 禁止跨模块 import 另一个 agent 未完成的页面（要用就等它交付，或抽到 `contracts/components`）
- 禁止格式化别人的文件

**退出条件**：各自目录 gate 绿（不接受「自报完成」——自述不是证据，只认 gate 终态）。

---

### Phase 4 — 集成（串行，1 个 Integrator）

按序执行：
1. 路由挂载 / 校验生成清单，比对 Phase 1 规划表，补齐缺失
2. store slice 接入根 store，检查 action 命名冲突
3. mock 切真实接口（按环境开关，不删 mock handler，保留给测试）
4. barrel 导出：`components/index.ts` 自动重生成 → 同名导出冲突处理
5. **语义去重**：同 path 重复注册、同 key 埋点、同 name 路由、重复导出
6. 清理 stub：计数归零
7. 全局兜底：404、错误边界、loading 骨架、空态统一
8. 跨页面跳转链路打通（列表 → 详情 → 编辑 → 回跳 + 刷新保持）

> 集成 agent 是最容易出错的岗位：它在没有原始上下文的情况下判断"两条重复注册留哪个"。所以 Phase 4 的产出必须全部由 Phase 5 验证，不接受自述完成。

---

### Phase 5 — 门禁（自动化，唯一可信的正确性证据）

一条命令跑完全链，任何一项失败即本轮不通过：

```
pnpm gate
 ├─ 1 contract-guard   禁止写入清单未被触碰（git diff）
 ├─ 2 ownership-guard  无越界写入（各任务只碰自己的目录）
 ├─ 3 deps-lock        package.json / lockfile 无新增
 ├─ 4 tsc --noEmit     类型
 ├─ 5 eslint           规范 + 命名约定（B 方案必备）
 ├─ 6 route-snapshot   实际路由清单 == 规划清单
 ├─ 7 dedup-check      路由/导出/埋点 key/store 字段语义去重
 ├─ 8 stub-count       占位 stub 归零
 ├─ 9 vite build       构建 + chunk 体积阈值
 ├─ 10 vitest run      单测
 ├─ 11 playwright test 关键路径 e2e（每模块 1 条主链路）
 └─ 12 视觉走查         截图对比（token 不一致在这里暴露）
```

`7 dedup-check` 是 C 策略的兜底，不能省。文本层能合并 ≠ 语义层能合并：git 对不同行追加很干净，于是两条同路径路由"成功合并"，实际是后者覆盖前者——这类 bug 不报错、只在特定 URL 偶发，最难查。

---

### Phase 6 — 定向修补（按归属回派）

> 编号对照：前端模式的「定向修补」在全栈模式为 Phase 7（全栈 Phase 6 = 发布验证）；门禁编号统一以 fullstack.md §8 为准（guard.sh 注释同口径）。

失败项按文件归属回到 **原 Implementer**，不要开新的 agent。上下文在它那儿，新 agent 要重新理解的成本高于修的成本。

回派消息只带三样：失败的门禁项编号 + 报错原文 + 涉及文件路径。

循环：Phase 5 → 6 → 5，直到全绿。连续两轮同一任务失败 → 该任务退回 Phase 2 重判契约，说明是契约问题不是实现问题。

---

## 3. 时间配比与节奏

- 串行（Phase 0/1/2/4/5/6）: 并行（Phase 3） ≈ **3 : 7**（纯前端口径经验值；含 Stage A/B 的全栈约 4 : 6）
- 常见做反：直接跳到并行，然后花一半时间在 Phase 4 擦屁股。
- 一个 12 页面的中型模块，健康节奏是 Phase 1+2 用掉整个迭代的前 1/3 时间。

---

## 4. 反模式清单（照着排除）

| 反模式 | 后果 | 正解 |
|---|---|---|
| 按层拆（一个写所有 API，一个写所有 UI） | 跨层耦合把并行变回串行 | 按业务纵向切 |
| 没定 design token 就并行写样式 | 合并时颜色/间距/尺寸全不一致，等于重写 | Phase 1 冻结 tokens |
| 多个 agent 碰同一个 store/context | 最难发现的 bug 来源 | slice 独占，注册表只读 |
| 把"改共享组件库"派成并行任务 | 它是所有人的上游 | 横切层串行 |
| Phase 3 中途改契约 | 要么全员停下重分发，要么这轮作废 | 变更回报 + 版本广播 |
| 依赖 agent 自述"已完成" | 假绿 | 只认 gate |
| 只加"不许改"不加变更通道 | agent 造局部 hack | 通道 + 广播 |
| 并行数盲目冲高 | 集成瓶颈吞掉收益 | 3 起步，逐轮验证 |
| 中间态基线是红的 | 每个 agent 都无法自验 | Phase 1 绿色基线 + stub |
| 用 C 策略但不做去重校验 | 语义冲突延迟到 e2e 才炸 | `dedup-check` 必配 |

---

## 5. 何时停止并行化（收益判断）

出现任一信号就回退到更少并行或更粗拆分：
- Phase 5 的失败里 **>30% 与集成/契约相关** → 契约没冻住，停并行回 Phase 2。
- Implementer 平均任务时长 <20 分钟 → 拆太细，传契约的成本已超过写代码的成本，合并任务。
- 每轮回派的文件 70% 集中在少数几个 → 那些是隐藏热点文件，改用 A/B 策略。
- 新增页面需要 Coordinator 手工接线的时间 > Implementer 写的时间 → 上 B 方案（约定式生成器）。

---

## 6. 交付物一览（每个阶段必须有实体文件）

| 阶段 | 交付物 |
|---|---|
| 0 | `docs/plan/page-tree.md`、`docs/plan/api-inventory.md`、`docs/plan/ownership.md` |
| 1 | 可运行骨架 + 绿色基线截图/log |
| 2 | `src/contracts/**`、`mock/**`、`docs/plan/contract-version.md` |
| 3 | 各任务目录 + 各自单测 + 任务交付报告 |
| 4 | 集成 diff + `docs/integration-notes.md`（重复项如何裁决） |
| 5 | `pnpm gate` 全绿 log + 视觉走查记录 |
| 6 | 回派记录（编号/报错/涉及文件/归属人） |

`integration-notes.md` 里必须记录"哪个重复注册被删了、为什么"——Phase 6 追查行为差异时全靠它。

---

## 7. 最小可用起步（不要一次上全套）

第一版只做这四件，已经能拿到 80% 收益（四件 = 纯前端最小集；全栈最小集七件见 SKILL.md「最小起步」）：
1. Phase 1 绿色基线（含 tokens + 请求层 + store 注册表）
2. Phase 2 契约冻结 + 禁止写入清单
3. 按页面拆分、目录独占的任务书
4. `gate` 里跑 contract-guard / ownership-guard / tsc / dedup-check

路由生成器（B）和 barrel 自动生成，等页面数超过 8～10 个再上——它们的维护成本在规模小的时候不划算。
