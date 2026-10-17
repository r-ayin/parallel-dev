# 模板包（复制即用）

---

## A. OWNERSHIP 矩阵 `docs/plan/ownership.tsv`

格式：`<agent-id><TAB><可写 glob>`，一行一条。guard.sh 用它做越界检查。
注意：glob 必须两两不重叠，这是并行的前提。

```tsv
# agent-id	glob
coord	src/app/**
coord	src/store/index.ts
impl-1	src/modules/order/pages/list/**
impl-1	src/modules/order/pages/detail/**
impl-2	src/modules/user/pages/list/**
impl-2	src/modules/user/pages/profile/**
impl-3	src/modules/report/pages/dashboard/**
impl-3	src/modules/report/pages/export/**
```

配套一页说明表（发给所有人）：

| 任务 ID | 页面 | 路由 name | slice | 接口 | 负责人 | 规模预估 |
|---|---|---|---|---|---|---|
| T-ORDER-LIST | 订单列表 | order-list | order | GET /api/orders | impl-1 | ~500 行 |
| T-ORDER-DETAIL | 订单详情 | order-detail | order | GET /api/orders/:id | impl-1 | ~400 行 |
| T-USER-LIST | 用户列表 | user-list | user | GET /api/users | impl-2 | ~450 行 |

可选强化（借 Chorus 的动作权限标注思路）：给上表加一列「阶段动作权限」——谁可提 CONTRACT_REQUEST、谁可标记 verified、谁可释放目录占用。动作权限与目录权限分离登记，避免「能写目录 = 能自我裁决」。

> glob 语义提醒：bash case 匹配中 `*` 跨 `/`（`src/modules/a/*` 也能匹配多级子目录），与 gitignore 直觉相反；声明时一律用 `/**` 结尾并依赖 guard.sh 的两两重叠检测。

---

## B. 任务书（Implementer 派发用）

```markdown
## T-ORDER-LIST 订单列表页

**目标**：运营人员可按状态/时间筛选并分页查看订单，点击行进入详情。

**非目标**（明确不做，防止顺手扩展）：
- 不做批量操作、不做列自定义、不做导出（导出是 T-REPORT-EXPORT）
- 不新增接口字段、不改表格组件

**人审检查点**：plan_checkpoint = 无（大任务/高风险任务可设「计划需人批后再派发」，检查点归 Coordinator 字段，Implementer 永不读写——BMAD checkpoint 纪律）

**契约（只读，禁止修改；不够用请提 CONTRACT_REQUEST）**：
- src/contracts/api/order.ts → `OrderListQuery` / `OrderListResp`
- src/contracts/routes.ts → route name: `order-list`
- src/contracts/store.ts → slice: `order`，state 字段 `list` / `query` / `total`
- src/contracts/events.ts → 埋点 key: `order_list_view` / `order_list_filter_click`

**允许写入路径**：
- src/modules/order/pages/list/**

**依赖 mock**：mock/handlers/order.ts（GET /api/orders），fixture 3 条 + 空态 + 500 错误各一份

**必须复用（不得自造）**：
- 表格：src/components/DataTable（props 见 contracts/components/data-table.ts）
- 请求：src/api/client.ts 的 `http.get`
- 样式：只能用 src/theme/tokens 里的变量，禁止硬编码色值/px

**验收标准（可执行，不接受口头完成）**：
- [ ] pnpm exec tsc --noEmit 通过
- [ ] pnpm exec vitest run src/modules/order/pages/list 全绿，含 4 个用例：正常渲染 / 空态 / 请求错误态 / 筛选触发重新请求
- [ ] pnpm exec playwright test tests/e2e/order-list.spec.ts 通过
- [ ] 无新增依赖、无越界文件改动

**交付格式**（首行机器可读 status，Coordinator 按字段路由，不读散文——BMAD terminal status 纪律）：
`status: done | blocked | halted | needs_contract_change`
改动文件列表 / 未尽事项 / 风险 / 是否需要契约变更（无则写 NONE）/ **本次我做但未写入契约的决定**（决策日志来源）
完整报告落盘 `docs/handoff/<任务ID>.md`，只向 Coordinator 回传 ≤1KB 摘要；每个「已完成」附 verifiedBy（确切命令 + 退出码），复核时重跑命令而非重读描述（contractor 纪律）
```

---

## C. CONTRACT_REQUEST（契约变更回报）

```markdown
ID: CR-014
提出人: impl-2
关联任务: T-USER-PROFILE
现状: src/contracts/api/user.ts 的 UserProfile 缺 avatarUrl 与 tags[]
影响面: T-USER-PROFILE（仅我）/ T-ORDER-DETAIL（会读 tags）
建议: 补 avatarUrl?: string; tags?: string[]
是否阻塞: 是（不阻塞则先按可选字段占位继续）

处理（Contract Owner 填写）：
裁决: 采纳 / 拒绝 / 延后到下个迭代
新版本: contract@v3
广播: 受影响任务 T-USER-PROFILE, T-ORDER-DETAIL → 需重新拉取契约
```

纪律：提出后 **不要自己造本地类型绕过**。若阻塞，允许在任务目录内临时 `// TODO(CR-014)` 占位并在交付报告里显式列出，Phase 4 由 Integrator 统一替换。

---

## D. 集成记录 `docs/integration-notes.md`

追查行为差异（前端模式 Phase 6 / 全栈模式 Phase 7）全靠这张表，必须记"删了哪个、为什么"。

```markdown
| # | 冲突类型 | 涉及项 | 裁决 | 理由 | 影响任务 |
|---|---|---|---|---|---|
| 1 | 路由 path 重复 | /orders 由 list 与 archive 同时注册 | 保留 list，archive 改 /orders/archive | 规划表定义 archive 为子路由 | T-ORDER-LIST |
| 2 | 同名导出 | OrderStatusTag ×2 | 保留 order/ 下，另一处重命名 OrderStatusMiniTag | 两者渲染不同 | T-ORDER-DETAIL |
| 3 | 埋点 key 重复 | order_list_filter_click ×2 | 合并为 1 处上报 | 同事件重复上报会污染指标 | T-ORDER-LIST |
| 4 | stub 残留 | src/modules/report/pages/export/index.tsx | 删除 PLACEHOLDER_STUB 并接入真实页 | — | T-REPORT-EXPORT |
```

---

## E. 契约版本 `docs/plan/contract-version.md`

```markdown
contract@v3 — 2026-10-16 — Contract Owner
变更: CR-014 采纳（UserProfile 增 avatarUrl/tags）
广播: 受影响 T-USER-PROFILE, T-ORDER-DETAIL → 重新拉取，旧任务产出需复验
基线: v3 之后 Phase 3 期间 contracts/ 冻结

contract@v2 — 2026-10-15 — CR-009 拒绝（新增分页排序字段改由前端本地排序）
contract@v1 — 2026-10-14 — 初始冻结
```

规则：**并行阶段中途改契约 = 该轮产出作废或全员停下重分发**。所以 Phase 2 宁可多花时间确认，也别在 v1 留模糊地带。

**升版必须附 SYNC IMPACT REPORT**（借 spec-kit constitution 机制）：每次升版除广播外，逐条列出下游影响核查——每个受影响任务书 / mock handler / e2e 用例标注 ✅ 仍有效 或 ❌ 需重分发。只广播不核查 = 隐性失配。

---

## F. Coordinator 派发循环（伪流程）

```text
Phase 0/1/2  串行完成，gate 绿，契约 v1 冻结
loop:
  取任务队列前 N 个（N = 当前并行度，起始 3）
  为每个任务生成任务书（模板 B），附只读契约路径 + 独占写入目录
  并行派发
  收集交付报告（文件列表 / 未尽事项 / CR 请求）
  处理 CR → 若采纳则升契约版本并重分发（本轮剩余产出需复验）
  Phase 4 接线 + 记录 integration-notes（模板 D）
  Phase 5 跑 gate
  gate 红 → Phase 6 按归属回派原 Implementer（只带：失败项编号 + 报错原文 + 文件路径）
  连续两轮同一任务失败 → 退回 Phase 2 重判该模块契约
  gate 绿 → 产出本轮 converge 判定（三态，借 spec-kit）：
    converged（全绿且无新 CR）/ progressing（全绿但有新 CR 或新任务）/ stalled（同任务连续两轮失败 → 熔断交人）
  converge ≠ stalled → 并行度 +1（上限 6），继续 loop

resume 路由（会话中断/重启后按交付报告 status 字段机械分派，借 BMAD resume 表）：
  done → 领取下一任务；blocked → Coordinator 裁决阻塞项；
  halted → 停止自动派发，交人；needs_contract_change → 走 CR 流程
```

回派消息示例：

```text
T-USER-PROFILE 回派（第 1 轮）
失败项: dedup-check
报错: slice name 冲突: user ← user.ts, userSession.ts
涉及: src/store/slices/userSession.ts
处理: 按契约 src/contracts/store.ts 的命名规范重命名 slice，不要改 contracts/
```
