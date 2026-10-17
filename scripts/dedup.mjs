// 语义去重：文本层能合并 ≠ 语义层能合并。
// 检查五类"git 不报冲突但行为会错"的重复注册。
// 用法：node scripts/dedup.mjs
// 对抗审计修复：模板字符串动态段归一化（${id} 与 ${userId} 视为同 path）、JSX 表达式容器
//   path={'/x'} 可见、slices 子目录递归、export * barrel 告警、埋点 key 允许连字符、
//   对象属性 path: 仅在路由语境文件中计数（面包屑/tab 配置不再误报）。
// 已知局限：变量间接（const P='/x'; path: P）静态不可见；跨文件路由顺序仅告警。
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import { join, relative } from 'node:path'

const ROOT = process.cwd()
const SRC = join(ROOT, 'src')
const problems = []
const warnings = []

function walk(dir, out = []) {
  if (!existsSync(dir)) return out
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules' || name === 'dist') continue
    const p = join(dir, name)
    const st = statSync(p)
    if (st.isDirectory()) walk(p, out)
    else if (/\.(ts|tsx|vue|js|jsx)$/.test(name)) out.push(p)
  }
  return out
}

const files = walk(SRC)
const read = (f) => readFileSync(f, 'utf8')
// 路由语境判定：文件里出现路由注册特征才把对象属性 path: 计入（防面包屑误报）
const ROUTE_CONTEXT = /<Route[\s/>]|createBrowserRouter|createRoutesFromElements|RouterProvider|useRoutes|element\s*:|component\s*:|\bel\s*:|loader\s*:|handle\s*:/
// 模板字符串动态段归一化：/users/${id} 与 /users/${userId} 归一为 /users/:_dyn
const norm = (p) => p.replace(/[$][{][^}]*[}]/g, ':_dyn')

// --- 1. 路由 path 重复注册（同 path 不同组件 → 后者静默覆盖前者）---
const routes = []
let order = 0
for (const f of files) {
  const src = read(f)
  const rel = relative(ROOT, f)
  const seen = []
  const ctx = ROUTE_CONTEXT.test(src)
  // JSX：<Route path="/x"> 与 <Route path={'/x'}>（本身即路由语境）
  for (const m of src.matchAll(/<Route\s+path\s*=\s*\{?\s*['"`]([^'"`]+)['"`]/g)) seen.push({ p: m[1], ctx: true })
  // 对象属性 path: '/x' —— 语境文件计 FAIL；非语境文件（面包屑/导航配置等）降级 WARN 人工核对，不静默丢弃
  for (const m of src.matchAll(/path\s*:\s*['"`]([^'"`]+)['"`]/g)) seen.push({ p: m[1], ctx })
  for (const s of seen) routes.push({ path: s.p, key: norm(s.p), file: rel, ctx: s.ctx, order: order++ })
}
const byKey = new Map()
for (const r of routes) {
  if (!byKey.has(r.key)) byKey.set(r.key, [])
  byKey.get(r.key).push(r)
}
for (const [k, rs] of byKey) {
  if (rs.length > 1) {
    const dyn = rs.some((r) => r.path !== r.key) ? '（动态段已归一）' : ''
    const detail = k + dyn + '\n    ' + rs.map((r) => r.path + ' @ ' + r.file).join('\n    ')
    if (rs.every((r) => r.ctx)) problems.push('route path 重复注册: ' + detail)
    else warnings.push('path 重复（非路由语境文件，可能是面包屑/导航配置，请人工核对）: ' + detail)
  }
}

// --- 2. 动态段吞噬静态段（/:id 排在 /new 前面 → /new 永远进不去）---
const warnOrder = []
for (const dyn of routes) {
  if (!dyn.key.includes(':')) continue
  const segs = dyn.key.split('/')
  const dynIdx = segs.findIndex((s) => s.startsWith(':'))
  if (dynIdx < 0) continue
  for (const st of routes) {
    if (st.key === dyn.key || st.key.includes(':')) continue
    const qs = st.key.split('/')
    if (qs.length !== segs.length) continue
    if (qs[dynIdx] === segs[dynIdx]) continue
    if (dynIdx > 0 && qs[dynIdx - 1] !== segs[dynIdx - 1]) continue
    if (dyn.file === st.file) {
      if (dyn.order < st.order) {
        problems.push('路由顺序错误: ' + dyn.file + ' 中动态段 ' + dyn.path + ' 排在静态段 ' + st.path + ' 之前 → ' + st.path + ' 将不可达')
      }
    } else {
      warnOrder.push(dyn.path + '(' + dyn.file + ') vs ' + st.path + '(' + st.file + ')')
    }
  }
}

// --- 3. barrel 同名导出 ---
const barrelFiles = files.filter((f) => /(^|\/)(components|api|utils|hooks)\/index\.(ts|tsx)$/.test(f))
for (const b of barrelFiles) {
  const src = read(b)
  const names = new Map()
  for (const m of src.matchAll(/export\s*\{([^}]*)\}/g)) {
    for (const raw of m[1].split(',')) {
      const n = raw.trim().split(/\s+as\s+/).pop().trim()
      if (!n || n.startsWith('//')) continue
      names.set(n, (names.get(n) || 0) + 1)
    }
  }
  for (const [n, c] of names) if (c > 1) problems.push('同名导出: ' + relative(ROOT, b) + ' → ' + n + ' (' + c + ' 次)')
  const starCount = (src.match(/export\s*\*/g) || []).length
  if (starCount > 1) warnings.push('barrel 含 ' + starCount + ' 条 export *（' + relative(ROOT, b) + '）：同名冲突静态不可判，集成期人工核对')
}

// --- 4. store slice / action 命名冲突（递归子目录）---
const sliceRoot = join(SRC, 'store', 'slices')
const sliceNames = new Map()
if (existsSync(sliceRoot)) {
  for (const f of walk(sliceRoot)) {
    const src = read(f)
    for (const n of src.matchAll(/name\s*:\s*['"`]([^'"`]+)['"`]/g)) {
      if (!sliceNames.has(n[1])) sliceNames.set(n[1], [])
      sliceNames.get(n[1]).push(relative(sliceRoot, f))
    }
  }
}
for (const [n, fs] of sliceNames) if (fs.length > 1) problems.push('slice name 冲突: ' + n + ' ← ' + fs.join(', '))

// --- 5. 埋点 key 重复使用（清单类，警告不阻断；允许连字符）---
const trackKeys = new Map()
for (const f of files) {
  for (const m of read(f).matchAll(/track\(\s*['"`]([\w.-]+)['"`]/g)) {
    trackKeys.set(m[1], (trackKeys.get(m[1]) || 0) + 1)
  }
}
const dupTrack = [...trackKeys].filter(([, c]) => c > 1)
if (dupTrack.length) {
  console.log('WARN 埋点 key 多处使用（确认是否同事件）:')
  for (const [k, c] of dupTrack) console.log('    ' + k + ' ×' + c)
}
for (const w of warnings) console.log('WARN ' + w)
if (warnOrder.length) {
  console.log('WARN 跨文件的路由动静段重叠，请确认最终注册顺序（静态段必须在动态段之前）:')
  for (const w of [...new Set(warnOrder)]) console.log('    ' + w)
}

if (problems.length) {
  console.error('FAIL 发现 ' + problems.length + ' 项语义冲突:')
  for (const p of problems) console.error('  - ' + p)
  console.error('\n→ 由 Integrator 裁决并在 docs/integration-notes.md 记录删除了哪个、为什么')
  process.exit(1)
}
console.log('OK 无语义冲突')
