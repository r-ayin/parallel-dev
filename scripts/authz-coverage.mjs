// authz 覆盖检查：新增/改动的 endpoint 必须带权限声明。
// 并行开发里 agent 极少主动写越权用例，故在门禁强制。
// 支持 Express/Koa 中间件式、NestJS/Spring 装饰器（守卫在路由装饰器上下皆可、容忍空行间隔）、
// FastAPI 依赖、Gin/Echo 大写式、Python @app.get 装饰器、多行路由声明、同行多个路由。
// 默认严格：缺权限 = FAIL（exit 1）。仅调试期用 AUTHZ_STRICT=0 降级为 WARN。
// 注释先剥离再判定：行尾 "TODO: add authz" / 注释里的 isPublic 不再算权限声明（对抗审计 F7 修复）。
// 用法：node scripts/authz-coverage.mjs
//   SCAN_ALL=1 全仓扫描（首次建基线）；SERVER_DIR 指定服务端目录；BASE_REF diff 基线（默认 origin/main）
// 已知局限：正则识别非 AST；router.route('/x').get() 链式注册、纯函数式路由表可能漏判，靠 review 层补。
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import { join, relative } from 'node:path'
import { execFileSync } from 'node:child_process'

const ROOT = process.cwd()
const BASE_REF = process.env.BASE_REF || 'origin/main'
const SERVER = process.env.SERVER_DIR || 'src/server'
const STRICT = process.env.AUTHZ_STRICT !== '0'
const BSL = 92 // '\\' 的 charCode，避免转义歧义

const AUTHZ_RE = /(\b(authz|authorize|permission|hasRole|requireAuth|ensureAuth|isAuthenticated|UseGuards|RequiresRoles)\b|@PreAuthorize|@Roles\b|@Auth\b|Depends\([^)]*[Aa]uth)/
const PUB_RE = /(^\s*@Public\b|@Public\(|\b(allowAnonymous|AllowAnonymous|noAuth|isPublic)\b)/m
// 文件级中间件：app.use(requireAuth) / router.use(jwtGuard) → 全文件 endpoint 视为已覆盖（对抗审计 F9b 修复）
const FILE_MW_RE = /(?:app|router|api)\s*\.\s*use\s*\([^)]*(?:auth|guard|session|permission|jwt|token)/i

const ROUTE_RES = [
  /(?:router|app|api)\s*\.\s*(get|post|put|patch|delete)\s*\(\s*['"`]([^'"`]+)['"`]/g,
  /@(GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|RequestMapping)\s*(?:\(\s*['"(]+\s*([^'"`)]*))?/g,
  /@(Get|Post|Put|Patch|Delete|Options)(?![A-Za-z])\s*(?:\(\s*['"`]([^'"`]*)['"`]\s*\))?/g,
  /\.(GET|POST|PUT|PATCH|DELETE)\s*\(\s*['"`]([^'"`]+)['"`]/g,
]

// 剥离注释但保留行数与字符串内容（字符串里的 // 与 /* 不动；http:// 不误剥）
function stripComments(src) {
  let out = ''
  let i = 0
  let inStr = null
  const n = src.length
  while (i < n) {
    const c = src[i]
    const c2 = i + 1 < n ? src[i + 1] : ''
    if (inStr) {
      if (c.charCodeAt(0) === BSL) { out += c + c2; i += 2; continue }
      if (c === inStr) inStr = null
      out += c; i++; continue
    }
    if (c === '"' || c === "'" || c === '`') { inStr = c; out += c; i++; continue }
    if (c === '/' && c2 === '*') {
      const end = src.indexOf('*/', i + 2)
      const stop = end === -1 ? n : end + 2
      out += src.slice(i, stop).replace(/[^\n]/g, ' ')
      i = stop; continue
    }
    if (c === '/' && c2 === '/') {
      if (out.endsWith(':')) { out += c; i++; continue } // http:// 等协议头
      const end = src.indexOf('\n', i)
      const stop = end === -1 ? n : end
      out += ' '.repeat(stop - i)
      i = stop; continue
    }
    out += c; i++
  }
  return out
}

function walk(dir, out = []) {
  if (!existsSync(dir)) return out
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules' || name === 'dist' || name === 'build' || name.startsWith('.')) continue
    const p = join(dir, name)
    const st = statSync(p)
    if (st.isDirectory()) walk(p, out)
    else if (/\.(ts|js|mjs|go|py|java|kt)$/.test(name)) out.push(p)
  }
  return out
}

function changedFiles() {
  if (process.env.SCAN_ALL === '1') return null
  try {
    // execFileSync 数组传参：BASE_REF 不再进 shell，杜绝命令注入（对抗审计 F1 修复）
    return execFileSync('git', ['diff', '--name-only', BASE_REF + '...HEAD'], { encoding: 'utf8' })
      .split('\n').filter(Boolean)
  } catch {
    console.warn('WARN git diff 失败（BASE_REF=' + BASE_REF + ' 无效或非 git 仓库），降级为全仓扫描（更严格，不放行）')
    return null
  }
}

const all = walk(join(ROOT, SERVER))
if (!all.length) {
  console.log('SKIP 未找到服务端目录 ' + SERVER + '（可用 SERVER_DIR 指定）')
  process.exit(0)
}
const changed = changedFiles()
const scope = changed ? all.filter((f) => changed.includes(relative(ROOT, f))) : all
if (!scope.length) { console.log('OK 本轮无服务端文件改动'); process.exit(0) }

const missing = []
for (const f of scope) {
  const src = stripComments(readFileSync(f, 'utf8'))
  const rel = relative(ROOT, f)
  if (FILE_MW_RE.test(src)) {
    console.log('INFO ' + rel + ': 检测到文件级鉴权中间件（app/router.use），本文件 endpoint 视为已覆盖')
    continue
  }
  const lines = src.split('\n')
  const lineStarts = [0]
  for (let k = 0; k < src.length; k++) if (src[k] === '\n') lineStarts.push(k + 1)
  const lineOf = (idx) => {
    let lo = 0, hi = lineStarts.length - 1
    while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (lineStarts[mid] <= idx) lo = mid; else hi = mid - 1 }
    return lo
  }
  // 先收集全部路由命中（多行声明可见），按位置排序；判定窗口 = 命中起点 → min(语句结束, 下一个命中起点)
  // 同行 app.get('/t1', requireAuth, h); app.post('/t2', h)：t2 的窗口不含 t1 的 requireAuth，不再串味（对抗审计 F7c/F7d 修复）
  const hits = []
  for (const re of ROUTE_RES) {
    re.lastIndex = 0
    let m
    while ((m = re.exec(src))) hits.push({ idx: m.index, end: m.index + m[0].length, path: m[2] || m[1] || '(annotated)' })
  }
  hits.sort((a, b) => a.idx - b.idx)
  const uniqHits = hits.filter((h, i) => i === 0 || h.idx !== hits[i - 1].idx)
  for (let hi = 0; hi < uniqHits.length; hi++) {
    {
      const h = uniqHits[hi]
      const m = { index: h.idx }
      const path = h.path
      const nextIdx = hi + 1 < uniqHits.length ? uniqHits[hi + 1].idx : src.length
      let stmtEnd = src.indexOf(');', h.end)
      stmtEnd = stmtEnd === -1 ? Math.min(h.end + 400, nextIdx) : Math.min(stmtEnd + 2, h.end + 400, nextIdx)
      const startLine = lineOf(h.idx)
      const endLine = lineOf(h.end - 1)
      let scopeText = src.slice(h.idx, Math.max(stmtEnd, h.end))
      // 上下装饰器窗口：容忍空行间隔（≤3 连续空行），装饰器重置计数（对抗审计 F9a 修复）
      for (let j = startLine - 1, blanks = 0; j >= 0 && blanks < 3; j--) {
        const t = lines[j].trim()
        if (t === '') { blanks++; continue }
        if (t.startsWith('@')) { scopeText = lines[j] + '\n' + scopeText; blanks = 0; continue }
        break
      }
      for (let j = endLine + 1, blanks = 0; j < lines.length && blanks < 3; j++) {
        const t = lines[j].trim()
        if (t === '') { blanks++; continue }
        if (t.startsWith('@')) { scopeText = scopeText + '\n' + lines[j]; blanks = 0; continue }
        break
      }
      if (!PUB_RE.test(scopeText) && !AUTHZ_RE.test(scopeText)) missing.push(rel + ':' + (startLine + 1) + '  ' + path)
    }
  }
}

// 越权用例覆盖提示：tests/ 下应能找到租户隔离类断言（纯 JS 扫描，不走 shell）
let hasCrossTenant = false
const testsDir = join(ROOT, 'tests')
if (existsSync(testsDir)) {
  const tFiles = walk(testsDir).slice(0, 500)
  hasCrossTenant = tFiles.some((f) => { try { return /tenant|otherUser|cross.?owner|403/.test(readFileSync(f, 'utf8')) } catch { return false } })
}

if (missing.length) {
  const tag = STRICT ? 'FAIL' : 'WARN'
  const fn = STRICT ? console.error : console.warn
  fn(tag + ' ' + missing.length + ' 个 endpoint 未见权限声明:')
  for (const x of missing) fn('    ' + x)
  if (STRICT) fn('    → 补权限注解或显式 @Public 标记；确属误报可用 AUTHZ_STRICT=0 临时降级（并行期不建议）')
  else console.log('    提示：当前为 AUTHZ_STRICT=0 调试模式；并行期默认严格（缺省权限视为高危）')
} else {
  console.log('OK 所有 endpoint 均有权限声明或显式 public 标记')
}
if (!hasCrossTenant) {
  console.warn('WARN tests/ 下未发现租户隔离/越权类断言（每个资源至少一条「A 访问 B 被拒」）')
}
process.exit(missing.length && STRICT ? 1 : 0)
