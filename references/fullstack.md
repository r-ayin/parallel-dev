# 全栈项目的多 Agent 并行开发：从 demo 到上线完整方案

> 覆盖：Stage A 页面 demo → Stage B 交互分析 → 三重契约冻结 → 全栈并行实现 → 集成 → 门禁 → 发布。
> 本版依据公开研究与工程实践对前稿做了修正，修正清单见 §1，未证实的经验值全部显式标注。

---

## §1 修正清单（相对前几轮对话）

| # | 原说法 | 修正 | 依据 |
|---|---|---|---|
| 1 | 并行上限 3～6 | 上限由「还有哪些决定没被规定」决定，不由任务数决定。数字仅作起点 | Cognition 两原则；Anthropic 明示编码可并行部分少于研究 |
| 2 | 假设清单只是 demo 附件 | 升级为跨 agent 传递决定的正式载体（决策日志） | Cognition：并行子 agent 因隐含假设冲突而失败 |
| 3 | 未提人审带宽 | 新增产出体积上限、按契约差异审查、初筛 reviewer agent | 高采用团队 PR 多 98% 但审查时间 +91% |
| 4 | 未提重复代码退化 | 门禁加重复度检查；Integrator 必交「抽象候选清单」 | GitClear：复制粘贴 8.3%→12.3%，移动行 约25%→不足10%（2021→2024；被引页为圆整值） |
| 5 | Stage A 由「你」裁决 | 改为外部任务式走查收敛，裁决人显式化为 Decider | Design Sprint：五天流程 + 与客户测试 + Decider/Facilitator |
| 6 | TBD 归零才准开发 | 残余 TBD 分流两类（需真数据 / 需拍板），不硬等归零 | 经验修正，原条件过严 |
| 7 | 3:7 / 4:6、2～4 轮收敛 | 标注为经验值，给出失效信号 | 无公开数据支撑 |

---

## §2 理论边界：什么时候能并行

**两条来自实践的第一性原则**由 Cognition 提出（2025-06）。 [Don’t Build Multi-Agents - Cognition](https://cognition.com/blog/dont-build-multi-agents)

1. **共享上下文，且共享完整 trace，而非单条消息。**
2. **动作携带隐含决定；互相冲突的隐含决定产出糟糕结果。**

由此推出本方案的准入判据：

> **可以并行的，只有「所有会影响他人的决定都已被规定」的部分。**

契约冻结的作用被重新定位：它不是流程仪式，而是**把「需要互相协调的决定」提前清零**的机制。Phase 2 之后 agent 之间只剩互不影响的决定，并行才成立。

Anthropic 的补充约束：多 agent 系统约用 15× 于普通对话的 token，单个 agent 约 4×；且多数编码任务真正可并行的部分比研究少，LLM agent 还不擅长实时互相协调与委派。所以并行是**用 token 换广度**，任务价值必须盖得过这份开销。 [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

### 合并成本三档（本方案的并行度模型）

| 合并方式 | 决定是否需要互相一致 | 成本 | 并行度 | 典型场景 |
|---|---|---|---|---|
| **选择式** 选一个、扔其余 | 不需要 | O(1) | 8～20 | demo 比稿、方案探索 |
| **汇总式** 只读同一份，各出报告 | 不需要 | O(n) | 4～8 | 交互扫描、安全走查、可达性审查 |
| **缝合式** 产出拼成一个可运行系统 | **强需要** | O(n²) | 3～6（受 §2 判据约束） | Phase 3 实现 |

> 注：三档模型是我提出的框架，非引用数据。它与 Anthropic「coding 可并行度低于 research」的观察方向一致。

**实操读法**：先问「这些产出最后怎么合」。比稿可以猛开；缝合必须先把决定做完再开。你觉得并行度上不去，几乎总是因为在缝合式任务上按比稿式直觉开 agent，撞到集成墙。

---

## §2.5 角色与拆分级别

### 角色

| 角色 | 数量 | 职责 | 权限 |
|---|---|---|---|
| Coordinator | 1 | 拆任务、发契约与决策日志、判定完成 | 全仓读写 |
| Contract Owner | 1（可与 Coordinator 同人） | 唯一可改 `contracts/` 与 OpenAPI | 仅契约层 |
| Design Owner | 1（可由 Coordinator 兼） | 唯一可改 tokens 与交互契约 | 仅 tokens / contracts/components |
| Implementer | 3～6 | 只写自己拥有的目录 | OWNERSHIP 中列出的路径 |
| e2e Writer | 1 | Phase 2 起凭状态机写场景 | `tests/e2e/**` |
| Integrator | 1 | Phase 4 接线、去重、抽象候选、清 stub | `src/app/**`、`store/index.ts`、barrel、migration 排序 |
| Reviewer | 自动化 + 1 人 | 跑 gate、视觉走查、判定回派 | 只读，产出报告 |
| Decider | 1（业务侧） | Stage A 方案取舍、Stage B 的 `DECISION-NEEDED` 拍板 | 不改代码 |

### 拆分级别

| 级别 | 单元 | 作并行任务？ | 说明 |
|---|---|---|---|
| L0 | monorepo package / 微服务 / 子应用 | 是 | 构建产物级隔离 |
| **L1** | **业务模块**（订单/用户/报表） | 主力 | 纵向自带完整链路 |
| **L2** | **feature 切片**（一条用例打穿 DB→API→UI） | **全栈主力** | 一个 agent 一个切片 |
| L2' | 单页面 或 单 endpoint 组 | 可以 | 大切片再拆时的下一层 |
| L3 | 组件 / DTO / migration | 不单独派 | 作为 L2 的附带产出 |
| L4 | hook / util / 类型 | 不单独派 | 附带；单独派会造重复实现 |
| 横切 | 设计系统、请求层、鉴权、中间件链、全局 store | **禁止并行** | 下游是所有人 |

判据：**纵向切，不横向切**。一个 agent 必须同时负责它的迁移、接口、页面、测试；让它只写前端或只写后端，就把 §2 的隐含假设冲突重新引回来了。


---

## §3 全链路总览

```
Stage A  页面 demo        高并行·选择式   产出 字段需求表 / 状态清单 / 决策日志
   ↓ 门禁：字段能否映射到数据模型；外部走查是否收敛
Stage B  交互分析          中并行·汇总式   产出 状态机 / 交互矩阵 / 异常清单
   ↓ 门禁：每条 TBD 已被归类（需真数据 / 需拍板），无「先这么做后面再定」
──────────────── 冻结点：契约第一次有证据支撑 ────────────────
Phase 1  基座骨架          串行           前后端脚手架 / 鉴权 / trace / env / CI / 绿色基线
Phase 2  三重契约冻结      串行           schema → OpenAPI → 可运行 mock → 交互契约
Phase 3  并行实现          中并行·缝合式   纵向 feature 切片（打穿 DB→API→UI→测试）
Phase 4  集成              串行           migration 线性化 / 真接口替换 / 去重 / 抽象候选
Phase 5  门禁              自动化         契约测试 / breaking change / 迁移演练 / authz / 重复度
   ↺ Phase 7 定向回派（gate 红则按归属回原 Implementer，循环至全绿）
Phase 6  发布验证          串行           flag 灰度 / 回滚演练
```

**e2e agent 在 Phase 2 就能开工**，不依赖实现：它只需要状态机和契约。这是全链路里最被浪费的一段并行机会。

配比（经验值，见 §12 失效信号）：A/B 约占周期前 25%～35%；串行段与并行段约 4:6。

---

## §4 Stage A — 页面 demo

**目的不是产出页面，是逼出字段清单和状态清单。** 页面本身是副产品。

### 4.1 规则（与实现阶段完全相反）

| 实现阶段 | demo 阶段 |
|---|---|
| 契约只读 | 鼓励违反既有假设 |
| 目录独占 | 允许随意造文件 |
| 禁止新增依赖 | 不限 |
| 必须带测试 | **明确禁止写测试** |
| 一套方案 | 3～10 套并列 |
| 门禁 = 构建+测试全绿 | 门禁 = 外部走查 |

### 4.2 必须真 / 必须假

| 必须真 | 必须假 |
|---|---|
| 数据形状：字段名、层级、可否空、超长文本、极端条数 | 接口（写死 JSON） |
| design token：色 / 间距 / 字号 / 断点 | 持久化 |
| 业务约束：某角色不可见哪些列、某状态不可操作 | 鉴权实现 |
| | 状态管理架构 |

理由：视觉方案推翻重来很便宜；**字段命名与数据形状写歪，到 Stage B 才暴露，代价是重写契约。**

### 4.3 三份真产出

1. **字段需求表** → 进数据契约。从界面反推：这个单元格要什么、这个筛选项映射哪个字段、这个统计该后端算还是前端算。
2. **状态清单** → 进交互契约。这个界面有几处「不一定是正常态」。
3. **决策日志 + 假设清单** → 防返工，并作为跨 agent 传递决定的载体（§2 原则 1 的落地）。

### 4.4 假设清单为什么是这里唯一的真风险

AI 会替你做几十个无声决定：分页默认大小、排序默认字段、空值显示成什么、时间格式、金额小数位、超长文本截断还是换行。这些不写在任何地方，却在 Stage B 和 Phase 3 反复引爆。**要求显式列出，是 Stage A 最重要的可交付物。**

### 4.5 收敛机制（修正版）

采用 Design Sprint 的角色结构：五天流程用于通过设计、原型和客户测试来回答关键业务问题（[The Design Sprint — GV](https://www.gv.com/sprint/)）。Decider（最终拍板人）与 Facilitator（流程主持）角色出自《Sprint》一书（Jake Knapp 等，2016）——gv.com/sprint 页面本身未展开角色定义。

映射到本方案：

| Sprint 环节 | 本方案 | 由谁做 |
|---|---|---|
| 理解/发散 | 并行 8～20 份 demo | 比稿式，产出互不合并 |
| 分诊+决定 | 走查后由 **Decider** 选一个 | 不许「都做保留」，选择式合并的前提是扔掉其余 |
| 试 | **外部任务式走查 ≥5 人次（经验值，无公开数据）** | 不是内部审美评审 |
| 记录 | 决策日志：为何选 A、B/C 输在哪 | 防三个月后旧方案被提回 |

关键修正：**收敛靠外部用户测试，不靠你和 agent 的判断。** 内部评审只会把 demo 变成审美磨盘。

---

## §5 Stage B — 交互分析

产出是一张**可冻结的交互契约**，不是一堆改稿建议。

### 5.1 动作一：把 demo 逆向成状态机

```
节点：idle / loading / empty / partial(分页中) / error(network|4xx|5xx)
      / forbidden / stale / submitting / optimistic-pending
边：  触发条件 → 状态转移 → 可见反馈
必须显式回答：
  - 哪个态能回哪个态，有没有死路
  - 并发触发（快速切 tab、重复提交、竞态返回乱序）走哪条边
  - 失败后表单数据保不保
  - 乐观更新失败的回滚路径
  - stale（数据过期）与 error 的视觉区分
```

价值：**状态机一画出来，缺态立刻可见。** demo 通常只画了 happy path，补全缺态就是 Stage B 的主要工作量。这张图直接就是 e2e 用例来源，不需二次翻译。

### 5.2 动作二：按维度并行扫描（汇总式，只读同一份 demo）

| 扫描维度 | 具体找什么 |
|---|---|
| 异常态穷举 | 零数据 / 单条 / 一万条 / 超长文本 / emoji / 全角 / null / 缺字段 |
| 权限可达性 | 无权限是隐藏还是 403；每个可点元素的键盘路径；焦点归位；aria-live |
| 断点适配 | 三档布局各自折叠规则；命中区尺寸；滚动冲突 |
| 反馈时机 | 校验在 blur 还是 change；toast 停留；提交后跳转还是原地 |
| 一致性 | 同一概念在不同页面叫法不同？同类操作反馈方式不同？ |
| 性能感知 | 哪些交互会被感知为卡；哪些需要乐观更新 |

### 5.3 动作三：交互矩阵

`元素 × 事件 × 状态变化 × 可见反馈 × 埋点 key`，一行都不许空着——**空格即未设计处**。

退出条件（修正版，不硬等归零）：每个 TBD 必须被打上两类标签之一：
- `DATA-NEEDED`：接真数据才能定 → 挂到 Phase 4 校验点
- `DECISION-NEEDED`：需 Decider 拍板 → 当场拍，不留

「先这么做，后面再定」这一类被禁止存在。

### 5.4 三重契约（冻结顺序不可颠倒）

| 序 | 契约 | 内容 | 产出 | 改权 |
|---|---|---|---|---|
| 1 | **数据契约** | 表、字段、索引、约束、migration 号段、软删策略 | schema / DDL | Contract Owner |
| 2 | **API 契约** | OpenAPI 或 protobuf、DTO、错误码、分页、幂等键 | spec + **可运行 mock** | Contract Owner |
| 3 | **交互契约** | design token、组件 props、状态语义表 | contracts/components + 状态机 | Design Owner |

**可运行 mock 是前后端能真并行的唯一前提。** 没有它，前端永远在等后端，并行度自动退化为 1。

第 0.5 层（最易漏、代价最高）——**统一数据语义约定**，一次写清：
时区与格式（UTC 存储 / 带 offset 传输 / 前端本地化显示）、空值（`null` vs 缺字段的语义差别）、金额与精度（分还是元、定点数、四舍五入归属方）、ID 策略（自增 / UUID / snowflake，前端可否解析顺序）、分页（offset vs cursor，总数要不要给）、错误码结构（机器码 + 人话 + 是否可重试）、命名转换（camelCase ↔ snake_case 由哪一层负责转换）。

这一项是**静默 bug 的主要产地**：agent 各自发明且不会报错。

---

## §6 全栈拆分与分配

### 6.1 单元是纵向 feature 切片，不是层

「前端 / 交互 / 后端 / 测试」是**分层**，而分层正是并行的头号反模式：一个 agent 写所有后端、另一个写所有前端，等于让两人隔着未定的接口互相猜，最后靠联调缝合。

并行单元 = 一条完整用例，打穿 `migration → handler → service → DTO → 页面 → 测试`。层级只是它的**写入范围列表**。

### 6.2 分配矩阵

| 资产 | 归属 | 可否并行 | 理由 |
|---|---|---|---|
| migration 文件 | 号段预分配：agent-N 用 `N00~N99` | **弱并行** | 全局唯一序列，冲突率最高，靠号段而非锁 |
| ORM model / entity | 与 feature 同 agent | 可以 | 每表一文件，天然不重叠 |
| API handler | 按 resource | 可以 | 注解式声明路由，热点比前端小 |
| service / domain | 与 feature 同 agent | 可以 | |
| DTO / mapper | 契约层 | **只读** | |
| 中间件 / 拦截器 | Phase 1 定稿 | **只读** | 横切 |
| 页面 / 组件 | 按页面 | 可以 | |
| e2e 场景 | 独立 agent，Phase 2 起并行 | 可以 | 只依赖契约 |
| seed / fixture | factory 模式，各 agent 自建 builder | 可以 | **禁止共享 seed 文件**（隐藏热点） |
| OpenAPI codegen 产物 | 只在 Phase 1/4 跑 | 只读 | 生成物必须确定性 |
| DI 容器 / module 注册 | 一次写全或约定式自动注册 | Phase 3 只读 | 同 routes 处理 |

### 6.3 配对策略

- 小 feature（≤3 页 + ≤5 endpoint）→ **单个全栈 agent 打穿**，上下文零损耗，最优解。
- 大 feature → 前端 agent + 后端 agent 配对，靠 mock 对齐。
- **不要为了并行数好看去拆小 feature。** 协调成本会超过收益，且拆开会重新引入 §2 的隐含假设冲突。

### 6.4 缺的六个环节（对「前端、交互、后端、测试」之外）

| 环节 | 为什么必须独立存在 | 缺了会怎样 |
|---|---|---|
| 领域建模与术语表 | 命名是全栈最贵的债 | `order/status/state` 混用，两表两服务两套说法 |
| 数据建模与迁移 | 全栈唯一强串行点；schema 最难改 | migration 手工线性化 = 悄悄改变执行语义 |
| 鉴权与权限模型 | 横切所有 endpoint 与页面 | 每个 agent 自造 session/token 处理，后期无法统一 |
| 数据语义约定 | 见 §5.4 第 0.5 层 | 静默 bug 主产地 |
| 可观测性（trace 贯穿） | 多人格产出唯一串联线索 | 并行后 debug 成本暴涨，只能猜 |
| 环境/配置/发布 | flag 命名、secret、迁移时机、回滚 | agent 跑不起来时开始造假数据自证通过 |

「测试」不是环节而是**三次投入**：Phase 2 写验收场景（当契约用）、Phase 3 各自写单元与契约测试、Phase 5 跑全链。当成独立并行阶段只会得到一堆断言 mock 行为的假绿。

---

## §6.5 热点文件治理：A / B / C 三种策略

并行崩掉的地方几乎都在**共享注册表**。这一节从前端方案继承，并扩展到全栈资产。三选一的本质是在决定**错误什么时候暴露**：A 逼到最前（最便宜），C 推到集成期（最贵）。

| 维度 | A 一次写全 + 冻结 | B 约定式 / 自动注册 | C 只追加 + 集成期排序 |
|---|---|---|---|
| 冲突 | 零 | 零（物理消失） | 仍有，只是变成语义冲突 |
| 串行成本 | 高（Phase 1 要穷举） | 中（Phase 1 搭生成器） | 低（只是纪律） |
| 可扩展并行数（经验值） | 3～5 | 最高，可推到 8+ | 名义高，实际受集成瓶颈限制 |
| agent 能否自验 | 能 | 能（但有假绿风险） | **不能**，中间态不可构建 |
| 不确定性容忍 | 差 | 好 | 最好 |
| 错误暴露时机 | 最早 | 中 | 最晚 |
| 显式性 / 可读性 | 最好，一眼看全 | 最差，规则在脑子里 | 中 |
| 基础设施依赖 | 无 | 重（插件、生成、缓存） | 依赖 git 行合并这个巧合 |

### 三者的关键缺陷

**A**：要求 Phase 0 就能穷举清单——而新页面、新 store 字段常是写着才出现的，不确定性全压到串行段。中间态构建不过（路由指向未创建的文件），必须用占位 stub 解决，代价是 Phase 4 要清残留。**必须同时配「禁止写入」+「变更回报通道」**：只给前者，agent 被堵住但需求真实存在，就会造局部 hack。

**B**：把显式配置换成隐式规则，而隐式规则对 agent 特别不友好——文件名成了公共 API，`detail.tsx` / `details.tsx` / `Detail.tsx` 混用**不会报错，只会让页面静默不存在**。所以用 B 必须补：① 命名 lint 规则；② 生成清单快照 + 与规划表 diff；③ 特例集中在 `routes.overrides.ts`，超过 10 条就退回 A。另有构建期生成类型的缓存/时机问题（agent 跑 tsc 可能拿旧清单，假绿），以及自动 barrel 让内部组件意外变公开 API。

**C**：**文本层能合并 ≠ 语义层能合并**。git 对不同行追加很干净，于是两个 agent 各加一条同路径路由、同名 store 字段，合并「成功」，实际是重复注册或后者覆盖前者。且每个 agent 无法自验，质量全押在集成 agent 身上，它又成了新的串行瓶颈。还依赖两个运气：插入点不相邻、追加顺序不影响行为（路由里 `/:id` 排在 `/new` 前面会直接吃掉静态路径——不报错、只在特定 URL 偶发）。
**C 真正适合的场合是「清单」而非「注册表」**：埋点 key、i18n 文案、图标名——多一条少一条不会导致行为错误，用「各自追加、集成期去重」完全划算。

### 判定顺序

1. 这份清单能在开工前穷举吗？→ 能，**A**
2. 结构能完全由文件名/路径表达、且有成熟框架支持吗？→ 是，**B**（可扩展性最高）
3. 都不行 → **C**，但门禁必须补语义去重 + 关键路径 e2e

### 全栈资产的分派表（本方案最终取值）

| 文件/资产 | 策略 | 阶段 | 写入权限 | 校验 |
|---|---|---|---|---|
| 前端路由表 | B（页面 >8）/ A（需精细 meta、权限、重定向） | Phase 1 定稿 | Phase 3 只读 | route-snapshot |
| 页面 meta / 权限 | A | Phase 1 | 只读 | tsc + snapshot |
| store 索引 `store/index.ts` | **A** | Phase 1 | 只读，slice 名与 state 类型定死 | tsc |
| slice 实现 | 各自独占 | Phase 3 | Implementer 独占 | 单测 |
| design tokens | **A，最严格** | Phase 1 | 任何人不得改 | dup-check 硬编码拦截 |
| 前端请求层 / 拦截器 | A | Phase 1 | 只读 | 单测 |
| barrel `components/index.ts` | B 自动生成，或 Phase 3 一律深路径 import、Phase 4 再生成 | Phase 4 | Integrator | dedup 同名导出 |
| API 类型 / DTO | A | Phase 2 冻结 | 只读 | tsc + contract-test |
| 后端 module / DI 注册 | B（注解自带）优先，A 兜底 | Phase 1 | Phase 3 只读 | 启动自检 |
| **migration** | **号段 A**（区间预分配，见门禁 5） | Phase 2 | 各 agent 限自己号段 | migration-range |
| 中间件链顺序 | A | Phase 1 | 只读 | 集成冒烟 |
| OpenAPI 规范 | A | Phase 2 | 只 Contract Owner | oasdiff |
| 埋点 key 清单 | **C** | Phase 3 | 各自追加 | dedup（告警） |
| i18n 文案 | **C**（按 namespace 分文件即可升为 A） | Phase 3 | 各自追加 | key 冲突校验 |
| seed / fixture | **C，但按 agent 分文件** | Phase 3 | 各自独占 | 无 |
| `package.json` / lockfile | **A，Phase 3 完全禁止** | Phase 1 | 无人可写 | deps-guard |
| 构建/环境配置 | A | Phase 1 | 无人可写 | — |

### 合并策略的补充建议

与其 branch-per-task 再做语义合并，更省事的是让并行 agent 在**同一沙箱、互不重叠的目录**里写，集成阶段直接就是最终态。合并冲突对 agent 而言几乎等于语义重写，值得专门绕开。

无论选哪个，Phase 1 结束时必须确立**绿色基线**（build 与 tsc 全绿）。A 和 B 天然有，C 没有——这才是 C 真正的弱点，不是合并冲突本身。

目录独占的更硬形态是 **git worktree per agent**（claude-squad / orca / emdash 等并行开发环境的行业做法）：每个 agent 挂同一仓库的不同 worktree，误写他人目录在文件系统层不可能，`ownership.tsv` 从唯一防线降级为第二道防线。任务粒度大、周期长时值得升级。

---

## §7 阶段详情

> Phase 0（结构化需求：页面树 / 数据流图 / 接口清单 / OWNERSHIP 初稿）与前端版一致，见 frontend.md「Phase 0」；本节从 Phase 1 开始。

### Phase 1 — 基座骨架（串行，只做一次）

1. 前后端目录结构 + 路径别名 + 一键起服务（含本地 DB / 容器编排）
2. `tsconfig strict`、lint、format、CI 流水线本身
3. 依赖与 lockfile **一次性装齐**，之后禁止新增
4. design tokens
5. 基础组件最小集：Button / Input / Select / Table / Modal / Form 壳 / Card / Skeleton / Empty / ErrorState
6. 请求层：client、拦截器、错误码映射、loading / 401、重试
7. **鉴权与权限模型落地**：token 流转、刷新、角色 → 可访问资源/操作映射、前端权限指令
8. store 骨架：slice 注册表、根 state 类型
9. 路由骨架 + 生成器（或一次写全）+ stub 页面
10. 后端模块注册骨架、DI 容器、配置加载、健康检查
11. **可观测性**：trace id 从前端请求头贯穿到网关/服务/DB 慢查询日志；结构化日志字段约定
12. migration 工具链 + 号段分配规则 + 影子库
13. MSW mock 接线与 handler 注册机制
14. 环境矩阵（local / ci / preview / prod）+ secret 注入方式 + feature flag 命名规范

**退出 = 绿色基线**：`pnpm gate` 全绿，stub 页面可访问，前后端本地互通。

> 骨架质量决定后面所有并行任务的一致性。宁可在这里多花时间。

### Phase 2 — 契约冻结（串行，最关键）

冻结：`contracts/domain/**`、`contracts/api/**`、`contracts/routes.ts`、`contracts/events.ts`、`contracts/store.ts`、`contracts/components/**`、数据语义约定、`mock/handlers/**` + `mock/fixtures/**`、schema 与 migration 号段。

三条纪律缺一不可：
1. 这些路径进入**禁止写入清单**（门禁 `git diff` 校验）。
2. **变更回报通道**：发现契约不够用只能提 `CONTRACT_REQUEST`，不允许绕过或另造。
3. 改完**广播版本号**，受影响任务重新分发。

> 只给 1 不给 2 是最常见失败：agent 被堵住但需求真实存在，于是造局部 hack，产出不一致实现。

**退出条件**：Implementer 不看后端文档也能独立开工并跑通 mock；e2e agent 能凭状态机写出用例。

### Phase 3 — 并行实现

派发前必答一题（§2 判据）：**这个任务里还有会影响别人的未定决定吗？** 有 → 回 Phase 2，别派。

- 每任务独占目录，两两不重叠（门禁校验）
- 规模：一个 feature 切片或一个页面
- 一 agent 一任务，完成再取下一个
- 每任务自带可执行验收
- **产出体积上限**：单任务 diff 超阈值（建议 800 行，经验值）必须拆分或分两轮交付 — 依据是审查时间随产出量显著上升（Faros 实测 +91%；「超线性」为经验判断，无公开数据支撑）

并行期禁止：改 contracts / theme / client / store 索引 / 路由表 / package.json；新增依赖；跨模块 import 未完成页面；格式化他人文件。

### Phase 4 — 集成（串行，1 个 Integrator）

1. migration 线性化（按号段与依赖排序），并**记录执行顺序是否被改变**
2. 路由挂载 / 校验生成清单 vs Phase 1 规划表
3. store slice 接入根 store，查 action 命名冲突
4. mock 切真接口（按环境开关，mock handler 保留给测试）
5. barrel 导出重生成 → 同名导出冲突
6. **语义去重**：同 path 重复注册、同 name 路由、同 key 埋点、重复导出
7. **抽象候选清单**：把并行期重复实现的位置列出来，标记「本轮抽象 / 下轮抽象」。不立刻重构——重构是横切动作，属于串行段
8. 清 stub，计数归零
9. 全局兜底：404、错误边界、loading、空态统一
10. 跨页跳转链路（列表→详情→编辑→回跳 + 刷新保持）
11. `DATA-NEEDED` 类 TBD 逐条验证
12. 失败切片清理：本轮废弃的切片正式 revert 到基线，并在 `ownership.tsv` 释放对应行（不留死代码占独占目录）

> Integrator 是最易出错的岗位：它在没有原始上下文时裁决「两条重复注册留哪个」。Phase 4 产出必须全由 Phase 5 验证，不接受自述完成。

### Phase 5 — 门禁

见 §8。**对会改状态的 agent 做终态评估而非逐轮检查**——不验证过程路径，验证最终状态是否达成（Anthropic 的工程实践）。这正是「只认 gate，不认自述」的形式化。

### Phase 6 — 发布验证

- feature flag 灰度（命名规范已在 Phase 1）
- **回滚演练**：迁移 up 之后必须演练 down；只测 up 的迁移方案等于没有回滚
- 可观测性验收：抽查一条真实请求，trace 是否贯穿
- 双轨开关：新旧接口并存期明确切换与摘除时点

### Phase 7 — 定向修补与回派（贯穿 5/6）

失败项按文件归属回到**原 Implementer**，不要开新 agent。上下文在它那儿，新 agent 重新理解的成本高于修的成本。

回派消息只带三样：**失败门禁编号 + 报错原文 + 涉及文件路径**。不带建议、不带情绪、不重述目标。

循环：gate → 回派 → gate，直到全绿。
- 连续两轮同一任务失败 → 退回 Phase 2 重判该切片契约（说明是契约问题不是实现问题）
- 同一门禁项在多个任务反复失败 → 是基建问题（tokens/请求层/测试夹具），交 Phase 1 的 owner 修，不要继续回派 Implementer
- 回派中出现「需要改只读路径」→ 只能走 CONTRACT_REQUEST，不许就地改

---

## §8 门禁完整清单

```
pnpm gate
 ├─ 1  contract-guard      只读路径未被触碰（git diff）
 ├─ 2  ownership-guard     无越界写入
 ├─ 3  deps-guard          package.json / lockfile 无新增
 ├─ 4  pr-size-guard       单任务 diff 体积上限（审查带宽）
 ├─ 5  migration-range     迁移号段未越界 + 线性化顺序未被偷改
 ├─ 6  oasdiff             OpenAPI 破坏性变更检测（字段删除/类型收窄/枚举缩水/必填化）
 ├─ 7  schema-drift        ORM model 与 migration 同源
 ├─ 8  authz-coverage      新增 endpoint 均有权限注解；缺省视为高危
 ├─ 9  contract-test       mock 与真实现行为一致（Pact / spec 校验）
 ├─ 10 dedup-check         路由/导出/埋点/slice 语义去重
 ├─ 11 duplication-check   代码重复度阈值（并行特化退化）
 ├─ 12 stub-count          占位 stub 归零
 ├─ 13 route-snapshot      实际路由清单 == 规划清单
 ├─ 14 tsc --noEmit        类型
 ├─ 15 eslint              规范 + 命名约定
 ├─ 16 lint-sql            禁 SELECT * / 强制分页上限 / 无索引告警 / N+1
 ├─ 17 secret-scan         密钥泄露
 ├─ 18 dep-audit           依赖漏洞
 ├─ 19 build + 体积阈值     产物
 ├─ 20 unit test           单测
 ├─ 21 e2e from 状态机      每个状态节点至少一条
 ├─ 22 越权用例            每资源至少一条 A 访问 B 被拒
 └─ 23 perf smoke          P95 阈值（防 dev 数据量下过、生产量下炸）
```

第 10、11 两项专门针对并行开发：**文本层能合并 ≠ 语义层能合并**；**多个 agent 各写一份相似实现是默认结局，不查就沉淀成债**。

脚本实现说明（均已实测）：

| 门禁 | 脚本 | 覆盖 | 已知局限 |
|---|---|---|---|
| 8 authz-coverage | `scripts/authz-coverage.mjs` | Express/Koa 中间件式、NestJS 装饰器（`@Get` + `@UseGuards`/`@Roles`/`@Public`，守卫在路由装饰器上下皆可）、Gin 大写式、FastAPI `Depends` | 正则识别，非 AST；纯函数式注册或极冷门写法可能漏判，靠 review 补 |
| 10 dedup-check | `scripts/dedup.mjs` | 同 path 重复注册、动态段吞噬静态段、barrel 同名导出、slice 撞名、埋点 key 重复 | 路由顺序仅同文件内判失败，跨文件降级告警（实际顺序由运行时拼接决定） |
| 11 duplication-check | `scripts/dup-check.mjs` | 硬编码色值/rgba/hsl（阻断）、魔法像素间距（告警）、跨文件重复块（接 jscpd） | 相似度检测不自己实现——那是需要调参的子课题，自研容易给出虚假的精确度 |
| 5 migration-range | `guard.sh` 内 | 文件名号段前缀是否落在 `docs/plan/migration-ranges.tsv` 分配区间 | 不校验迁移内容冲突，只保证不会抢同一序列 |

首次建立基线用 `SCAN_ALL=1`（跳过 diff，全仓扫描）；authz 默认严格（缺权限 = FAIL，exit 1），仅调试期用 `AUTHZ_STRICT=0` 降级为告警。

**§8 清单与脚本的对应关系**（避免误以为装上就能跑全部）：

| §8 编号 | 项 | 由什么实现 |
|---|---|---|
| 1-6 | contract / ownership / deps / pr-size / migration-range / oasdiff | `guard.sh`（oasdiff 需外部命令） |
| 8 | authz-coverage | `authz-coverage.mjs` |
| 10 | dedup-check | `dedup.mjs` |
| 11 | duplication-check | `dup-check.mjs`（跨文件块需 `pnpm add -D jscpd`） |
| 12-13 | stub-count / route-snapshot | `guard.sh`（route-snapshot 需自建 `gen-routes.mjs`） |
| 14-15, 19-21 | tsc / eslint / build / unit / e2e | `guard.sh` 按项目能力调度（缺包管理器/配置/e2e 目录时 SKIP 而非误报） |
| **7, 9, 16-18, 22-23** | schema-drift / contract-test / lint-sql / secret-scan / dep-audit / 越权用例 / perf smoke | **接项目已有工具**（Prisma drift、Pact、sqlfluff、gitleaks、audit、Playwright、k6）；第 21 项的状态机节点比对需自建映射脚本。`guard.sh` 头部已标注未实现项，不留假接口 |

### §8.5 并行同行强化条款（吸收自开源同行 contractor 的 docs/invariants.md，每条在其原项目都有真实翻车案例佐证）

1. **两轮熔断 + 现场固化**：同一任务连续两轮 gate 失败即停止回派循环，把现场固化到 `debug/<任务>-stuck` 分支并在交付报告标 `status: halted` 交人裁决。**轮次计数器必须与回派日志条数一致**——计数器落后 = 门禁自身报错（防止回派轮次被静默漏记而解除熔断）。
2. **验证产物原始落盘**：gate 的逐项 verdict/退出码原始输出先写盘（如 `.gate/verdict-<round>.json`）再允许读取派生结论；**缺失 verdict 文件 = FAIL，绝不假定 pass**。boundaryViolations / missingDefaults 类字段是硬阻断。
3. **集成 gate 先清缓存**：增量构建缓存会让编译器跳过已触碰文件产生假绿；Phase 4/5 跑 gate 前清相关缓存，且集成测试范围从 commit 全集派生，而非「谁碰过哪些目录」的 touched-area 集合（无人认领的变更路径会让 area 套件全绿而整体红）。
4. **verifiedBy 可重跑**：每个「已完成」声明附确切命令 + 退出码（verifiedBy 字段），复核者与 gate 直接重跑这些命令，不重读散文。警惕三种静默 no-op：批量编辑工具静默失败、staging 未变更文件 exit 0、migration 绕过 schema 声明。
5. **交付落盘 + digest 回传**：Implementer 把交付报告全文写进自己目录（如 `docs/handoff/<task>.md`），只向 Coordinator 回传 ≤1KB 摘要（文件清单 / status / 风险 / CR 请求），省主会话上下文。

### §8.6 语义评审层（确定性门禁的补充，吸收自 awslabs/aidlc-workflows 的多镜头 PR review 机制）

正则门禁认不出冷门写法与语义错误（上表已标注各脚本局限）。在其上补一层制度化 LLM 评审：
- **镜头拆分**：按 scope（越界/契约符合性）、security（注入/越权/密钥）、UX（状态/反馈/可达性）分派独立只读 reviewer，彼此不共享上下文——共享上下文 = 共享盲区，一个窗口扮演多个评审会多次漏掉同一处。
- **schema 判卷**：评审输出固定 JSON（finding/severity/evidence/verdict），由一个 judge 汇总为单一可发布 verdict；verdict 同样原始落盘（§8.5 第 2 条）。
- **台账**：评审结果追加进 `docs/review-ledger.md`，可追溯「哪轮哪些文件被哪个镜头看过」。
- 这一层不替代 guard.sh 也不替代人，只补两者之间的语义盲区；镜头 prompt 组织方式参考 aidlc 的 .github/prompts/ai-pr-review-*.md。

> 第 21 项（每个状态节点至少一条 e2e）无法用静态脚本判定——它依赖 Stage B 的状态机产物。做法是把状态机转成矩阵表存 `docs/plan/state-machine.md`，e2e 用例命名带节点名（`order-list.stale.spec.ts`），再用**自建比对脚本**核对节点数与用例文件数（`guard.sh` 不含该逻辑，与 `gen-routes.mjs` 同属项目自建项）。这是本方案里唯一需要人工维护映射的一项。

---

## §9 成本与带宽（并行开发的真实约束）

| 约束 | 实测/公开数据 | 对方案的影响 |
|---|---|---|
| token 消耗 | 多 agent 约 15× 于对话，agent 约 4×（Anthropic） | 任务价值必须盖过开销；比稿便宜（读多写少），缝合昂贵 |
| 审查带宽 | 高采用团队任务 +21%、PR +98%，审查时间 +91%（Faros AI） | 产出体积上限（门禁 4）；按契约差异审而非代码差异审；初筛 reviewer agent |
| 代码质量漂移 | 复制粘贴 8.3%→12.3%；代表重构的移动行 约25%→不足10%（GitClear；精确小数在报告 gated PDF 内，被引页为圆整值） | 重复度门禁 + 抽象候选清单 + 显式「本轮不重构」纪律 |
| 自述可信度 | 资深开发者 RCT 实测慢 19%，预期快 24%、事后仍认为快 20%（METR） | 不接受任何 agent 自评完成度；只认终态门禁 |
| 稳定性 | DORA 2025：AI 采用与吞吐转为正相关，但与交付不稳定性同为正相关；30% 开发者对 AI 代码低信任 | **吞吐量与事故率会一起涨**，除非门禁收紧；发布阶段的灰度与回滚演练是必需的，不是可选 |

数据来源：token 与编码可并行度 [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)；审查带宽 [The AI Productivity Paradox Research Report](https://www.faros.ai/blog/ai-software-engineering)；重复与移动行 [AI Copilot Code Quality: 2025 Data Suggests 4x Growth in ...](https://www.gitclear.com/ai_assistant_code_quality_2025_research)；自述与实测差 [Measuring the Impact of Early-2025 AI on Experienced ...](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/)；吞吐与不稳定性同向 [Announcing the 2025 DORA Report | Google Cloud Blog](https://cloud.google.com/blog/products/ai-machine-learning/announcing-the-2025-dora-report) [Balancing AI tensions: Moving from AI adoption to effective SDLC use](https://dora.dev/insights/balancing-ai-tensions/)

> 这一节是全方案里最容易「看起来完成了、实际在退步」的部分。指标必须看**交付后的**（变更失败率、回滚次数、缺陷逃逸），不能只看过程量（提交数、PR 数、生成行数）。

---

## §10 反模式（扩充版）

| 反模式 | 后果 | 正解 |
|---|---|---|
| 按层拆（各自包揽前端/后端/测试） | 隔着未定接口互猜，靠联调缝合 | 纵向 feature 切片 |
| demo 用内部审美评审收敛 | 变成磨盘，轮次失控 | 外部任务式走查 ≥5 人次 |
| demo 代码沉入主干 | 硬编码假数据变生产 bug | 三不沉：代码/依赖/硬编码数据 |
| 不要求假设清单 | 几十个无声决定在 Phase 3 引爆 | 交付必附假设清单 |
| 没定 design token 就并行 | 颜色/间距/尺寸全不一致 | Phase 1 冻结 |
| 让 agent 并行写 migration 序列 | 手工线性化，执行顺序被偷改 | 号段隔离 + 记录顺序变更 |
| 共享 seed 文件 / 共享测试库 | 互相污染，只在 CI 复现的随机失败 | 各 agent 独立 builder / 独立库或事务回滚 |
| 多个 agent 碰同一 store/context | 最难发现的 bug | slice 独占，注册表只读 |
| 把「改共享组件库」派成并行任务 | 它是所有人的上游 | 横切层串行 |
| Phase 3 中途改契约 | 全员停下重分发或本轮作废 | 变更回报 + 版本广播 |
| 每个 agent 自己 codegen | 生成物不一致，大面积伪 diff | codegen 只在 Phase 1/4 跑 |
| 鉴权「最后统一处理」 | 它是所有 endpoint 的上游 | Phase 1 落地 |
| e2e 到 Phase 4 才写 | 只能照已实现代码写断言，失去验收作用 | Phase 2 起并行 |
| 靠提交数/PR 数证明收益 | 审查带宽与缺陷率被忽略 | 只看交付后指标 |
| agent 自述完成即通过 | 假绿 | 终态门禁 |
| 用 C 策略不做去重校验 | 语义冲突延迟到 e2e 才炸 | 必配 dedup-check |

---

## §11 实例走查：一个「订单中心」模块

### Stage A（并行 6 份 demo）

需求原话：「运营要能看订单、按状态筛、点进去能改备注。」

三份代表性产出：A 列表为主（表格+行内操作）、B 看板为主（状态列拖拽）、C 列表 + 右侧抽屉详情。

字段需求表（节选，A 版）：

| 界面元素 | 字段 | 类型 | 可空 | 来源猜测 | 备注 |
|---|---|---|---|---|---|
| 订单号列 | `orderNo` | string | 否 | orders.order_no | 18 位，需可复制 |
| 状态标签 | `status` | enum | 否 | 枚举需确认 | **A 版用了 5 个状态，需求没给全** |
| 金额列 | `amountCents` | int | 否 | orders.amount | **假设以分为单位**，需确认 |
| 时间列 | `createdAt` | string | 否 | orders.created_at | **假设为 ISO8601 带 offset**，需确认 |
| 筛选-时间 | `dateFrom`/`dateTo` | string | 是 | query 参数 | 假设闭区间 |
| 统计条 | `pendingCount` | int | 否 | 谁算？ | **未定：后端聚合 or 前端遍历** |

假设清单（A 版，12 条，节选）：分页 20 条默认；排序默认 `createdAt desc`；空值显示 `—`；超长订单号截断+tooltip；状态可点击筛选；行内「改备注」为弹窗非抽屉；导出按钮置灰而非隐藏；移动端不支持操作。

走查结果：5 人次任务式测试，4/5 在 B 版上找不到「改备注」入口 → **B 淘汰**（看板拖拽把编辑操作藏进了拖拽语义）。A/C 进 Stage B 融合。

决策日志：放弃 B，因编辑类操作的可见性不足；保留 C 的抽屉方案（可在详情内直接编辑，省去二次弹窗），保留 A 的筛选区（更完整的组合条件）。

### Stage B

状态机（订单列表，节选）：

```
idle → loading → ready
loading → error{network|401|403|5xx}
ready → filterChanged → loading（保留旧数据 + 顶部进度条，不清空表格）  ← 原 demo 是清空表格，闪烁
ready → submittingNote → optimistic-pending → {applied | rolled-back}
rolled-back → toast(错误原因) + 恢复原值 + 保留用户输入
任意 → stale（轮询发现版本变化）→ 顶部提示条，不打断操作
并发：快速切 tab → 乱序返回必须丢弃旧请求（reqId 比对）  ← demo 未实现，属缺陷
```

发现 4 个 demo 缺失态：`stale`、`partial`（分页加载中保留旧行）、`forbidden`（列级权限）、`rolled-back`。

交互矩阵中产生 3 条 TBD：
- `pendingCount` 由谁算 → `DECISION-NEEDED` → Decider 当场拍：**后端聚合**（数据量级会超 10 万）
- 备注长度上限与超限行为 → `DATA-NEEDED` → Phase 4 校验点
- 时间列显示时区（本地还是 UTC+8 固定）→ `DECISION-NEEDED` → 拍：**本地时区显示，存储 UTC**

### Phase 2 冻结（节选）

```ts
// contracts/api/order.ts
export interface OrderListQuery {
  status?: OrderStatus; dateFrom?: string; dateTo?: string;   // ISO8601, 闭区间
  cursor?: string; limit?: number;                             // 默认 20，上限 100
}
export interface OrderListResp {
  items: OrderSummary[]; nextCursor?: string;
  pendingCount: number;                                        // 后端聚合，已拍板
}
export type OrderStatus = 'pending'|'paid'|'packing'|'shipped'|'closed';  // 5 态，来自走查确认
```

migration 号段：订单 agent 用 `100~199`，用户 agent 用 `200~299`。
mock：`GET /api/orders` 提供 4 份 fixture（正常 20 条 / 空 / 500 / 权限受限）。

### Phase 3（并行 4 个 feature agent）

| agent | 切片 | 写入范围 |
|---|---|---|
| f1 | 订单列表 + 筛选 + 备注编辑（前端） | `src/modules/order/pages/list/**` |
| f2 | 订单列表 API + 聚合 + migration 100-119 | `src/server/order/list/**`、`migrations/1[0-1]*` |
| f3 | 订单详情（前后端一体，打穿） | `src/modules/order/pages/detail/**` + `src/server/order/detail/**` + `migrations/120-139` |
| e2e | 凭状态机写 11 条场景（含 4 个新补态） | `tests/e2e/order/**` |

f1 上报 `CONTRACT_REQUEST`：`amountCents` 需要展示币种。裁决采纳，升 `contract@v2`，广播至 f1/f3 复验。

### Phase 4 集成记录（节选）

| # | 类型 | 涉及 | 裁决 | 理由 |
|---|---|---|---|---|
| 1 | 路由重复 | `/orders` 由 list 与 archive 同时注册 | archive 改 `/orders/archive` | 规划表定义为子路由 |
| 2 | 路由顺序 | `/orders/:id` 排在 `/orders/new` 前 | 调整静态段优先 | 否则 `/new` 不可达 |
| 3 | 重复实现 | f1 与 f3 各写一份金额格式化 | 抽到 `src/utils/money.ts`，登记抽象候选 | 本轮抽取（成本低）；同类 5 处仅登记 |
| 4 | 语义分歧 | f2 返回 UTC 无 offset，f1 按本地解析 | 后端补 `Z` 后缀 + 契约测试覆盖 | Stage B 已拍「存储 UTC、显示本地」 |
| 5 | migration | f2/f3 号段交错，执行顺序与提交顺序不同 | 按号段排序，**记录顺序变更** | 线性化不得悄悄改语义 |

### Phase 5 命中

`oasdiff` 阻断一次（f2 把 `items` 从必填写成可选）；`越权用例` 抓到 f2 未校验租户隔离；`duplication-check` 报出 3 处相似表格封装，1 处已抽，2 处登记下轮。

这轮的价值在于：**这 5 个问题里有 4 个是在并行开发里必然出现、且不会以「冲突」形式提示你的。**

---

## §11.5 交付物清单（每阶段必须有实体文件，否则该阶段视为未完成）

| 阶段 | 交付物 | 被谁消费 |
|---|---|---|
| Stage A | `prototype/<模块>/plan-<X>/`、字段需求表、假设清单、走查记录、决策日志 | Stage B、Phase 2 |
| Stage B | 状态机 `docs/plan/state-machine.md`、交互矩阵、异常清单、TBD 归类表 | Phase 2 契约、e2e Writer |
| Phase 1 | 可运行骨架 + 绿色基线 log、`docs/plan/data-semantics.md`、env 矩阵、trace 样例 | 全体 |
| Phase 2 | `src/contracts/**`、OpenAPI、`mock/**`、schema + 号段表、`contract-version.md` | Implementer、e2e |
| Phase 3 | 各切片目录 + 单测 + 契约测试 + **交付报告（含本轮新增决定）** | Integrator、Coordinator |
| Phase 4 | 集成 diff + `integration-notes.md`（裁决记录）+ **抽象候选清单** + migration 顺序变更记录 | Reviewer、后续迭代 |
| Phase 5 | `pnpm gate` 全绿 log + 视觉走查记录 | Coordinator 判定合并 |
| Phase 6 | 灰度计划、回滚演练 log、flag 摘除时点 | 运维 |
| Phase 7 | 回派记录（门禁编号 / 报错 / 文件 / 归属人 / 轮次） | 度量契约质量 |

`integration-notes.md` 必须记「删了哪个、为什么」——Phase 7 追查行为差异全靠它。
`decisions.log` 必须每轮更新——它是 §2 原则 1 唯一可执行的近似实现。

**demo 产物的三不沉**（在 git 层面拦住，不靠自觉）：
1. `prototype/**` 进 `.gitignore`（或独立 orphan branch），绝不进主干
2. demo 新增的依赖不得出现在主干 lockfile —— 用 `pnpm install --frozen-lockfile` 在 gate 卡住
3. demo 的硬编码假数据不得进 `mock/fixtures/` —— 由 dup-check 的硬编码色值检查 + fixture 文件来源标注共同兜

---

## §12 度量与失效信号

**唯一的过程指标**：Phase 3 之后退回 Phase 2 改契约的次数。应逐轮收敛。它高 = Stage A/B 被跳过或门禁放水。

其他信号：

| 信号 | 判读 | 动作 |
|---|---|---|
| 门禁失败 >30% 与契约/集成相关 | 契约没冻住 | 停并行，回 Phase 2 |
| 单任务平均耗时 <20 分钟 | 拆太细，传契约成本已超过写代码成本 | 合并任务 |
| 回派文件 70% 集中在少数几个 | 隐藏热点文件 | 该文件改一次写全/约定式 |
| 新增一页需 Coordinator 手工接线时间 > 写的时间 | 注册表成瓶颈 | 上自动注册 |
| demo 轮次 >5 | 需求方未决定要做什么 | 停止迭代，这是流程问题 |
| 字段需求表连续一轮零变化 | 数据契约已收敛 | 可冻结 |
| 审美/偏好类反馈占比 >50% | 语义问题已解决干净 | 可冻结，继续改只是打磨 |
| TBD 数量开始下降而非清零 | 剩余分歧需真数据 | 转 `DATA-NEEDED` 归档，进 Phase 1 |
| **变更失败率 / 回滚次数上升** | 吞吐量涨了但不稳定性也涨（DORA 观察到的形态） | 收紧门禁，加灰度粒度，降并行度 |
| 审查排队变长、PR 存活时间上升 | 撞上审查带宽墙 | 降产出体积上限、加初筛、降并行度 |

**经验值声明**：`3:7 / 4:6` 的串并配比、`2～4 轮` demo 收敛、`3～6` 缝合式并行度，以及上表各阈值（>30%、<20 分钟、70%、>5 轮、>50%）、§4.5 的 ≥5 人次走查、§6.5 的策略并行数（3~5 / 8+）与 §7 的 800 行 diff 上限，均为实践启发式，无公开数据支撑。以上表给出各自失效信号，按信号调整而非按数字坚持。

---

## §13 最小起步（不要一次上全套）

第一批只做七件：
1. Stage A/B 各一份任务书 + 假设清单要求（这是全链路里杠杆最大、成本最低的一段）
2. Phase 1 绿色基线（tokens + 请求层 + 鉴权 + trace + store 注册表）
3. Phase 2 契约冻结 + 禁止写入清单 + 变更回报通道
4. 纵向 feature 切片 + 目录独占的任务书
5. 门禁里的：contract-guard、ownership-guard、tsc、dedup-check
6. 门禁里新加的：authz-coverage、oasdiff、duplication-check（全栈三项，成本极低收益极高）
7. 只看交付后指标（变更失败率、回滚次数），不看过程量

延后：自动路由/注册生成器、迁移号段强校验、性能 smoke、视觉走查自动化——等规模或痛点到了再上。

---

## 来源

**Agent 编排与并行边界**
- Don't Build Multi-Agents — Cognition, Walden Yan, 2025-06-12：share context / actions carry implicit decisions；并行协作在 2025 年产出脆弱系统；Claude Code 的子 agent 通常（usually）只答问题不写代码。https://cognition.com/blog/dont-build-multi-agents
- How we built our multi-agent research system — Anthropic, 2025-06-13：orchestrator-worker；agent 约 4×、多 agent 约 15× token；两种并行化（lead agent 并行开 3-5 个 subagent + subagent 并行用 3+ 工具）使复杂查询耗时降低最多 90%；多数编码任务可并行部分少于研究；委派需含目标/输出格式/工具指引/任务边界；终态评估；产物写文件系统以减小「传话游戏」损耗。https://www.anthropic.com/engineering/multi-agent-research-system

**产出与质量的实测数据**
- The AI Productivity Paradox Research Report — Faros AI：高 AI 采用团队任务完成 +21%、合并 PR +98%、PR 审查时间 +91%。https://www.faros.ai/blog/ai-software-engineering
- AI Copilot Code Quality 2025 — GitClear：copy/pasted 占比 8.3%→12.3%，moved lines 约25%(2021)→不足10%(2024)，2024 年提交内复制首超移动（精确小数 24.1/9.5 见报告内页图表，公开被引页仅圆整值）。https://www.gitclear.com/ai_assistant_code_quality_2025_research
- Measuring the Impact of Early-2025 AI on Experienced Open-Source Developers — METR RCT：用 AI 慢 19%；预期快 24%、事后仍认为快 20%。https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/
- 2025 DORA Report / Balancing AI tensions：AI 采用与吞吐转为正相关但不稳定性维持高位；30% 开发者对 AI 生成代码低信任。https://cloud.google.com/blog/products/ai-machine-learning/announcing-the-2025-dora-report ；https://dora.dev/insights/balancing-ai-tensions/

**契约优先 / 规格驱动**
- Spec-driven development toolkit — GitHub Blog：规格而非代码作为主要产出物。https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/
- From Code to Contract in the Age of AI Coding Assistants — arXiv：SDD 反转传统流程，代码成为被生成的工件。https://arxiv.org/html/2602.00180v1
- API Contract Testing — oasdiff 在合并前区分破坏性/非破坏性变更；Pact 为消费者驱动契约的标准选择。https://stevekinney.com/courses/enterprise-ui/api-contract-testing

**需求发现与原型**
- The Design Sprint — GV：五天流程，通过设计、原型与客户测试回答关键业务问题。https://www.gv.com/sprint/ （注：Decider/Facilitator 角色文字出自《Sprint》一书 2016，被引页面无角色定义；library.gv.com 已不可达）
- Prototyping（MIT 6.813 讲义）：原型远快于完整实现，因而可更早评估并获得反馈。https://web.mit.edu/6.813/www/sp16/classes/10-prototyping/

**同类生态调研**
- 本技能的同类开源项目调研与吸收清单（contractor / adhd / BMAD / aidlc / spec-kit / claude-squad 等，含核实深度分级与合并落点）见 `references/ecosystem.md`。

**未证实而保留的原则**
- 「原型必须可抛弃，不得长成生产代码」这条原则在原型设计文献中广泛流传（常见表述如 "prototype or kill it"），本次检索未能定位到可靠原始出处，故本方案只采用原则本身，不挂人名。
