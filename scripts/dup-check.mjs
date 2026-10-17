// 重复度检查。两个部分：
//  A) 硬编码样式 —— 并行开发最容易「各写一份」且能精确检测的一项，直接失败。
//  B) 跨文件重复块 —— 若安装了 jscpd 则用它给量级；没有则跳过并提示安装。
// 对抗审计修复：SRC_DIR/DUP_THRESHOLD 不再进 shell（execFileSync 数组传参，杜绝注入）；
//   块注释/行尾注释剥离（http:// 不误剥）；CSS 选择器行的 #id 不再当色值；
//   __tests__/__mocks__/.stories. 排除；svg fill/stroke 属性色降级 WARN。
// 说明：本脚本刻意不自己实现相似度检测（那是个需要调参的子课题）。
// 用法：node scripts/dup-check.mjs
//   DUP_THRESHOLD=5  SRC_DIR=src  node scripts/dup-check.mjs
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import { join, relative } from 'node:path'
import { execFileSync } from 'node:child_process'

const ROOT = process.cwd()
const SRC = process.env.SRC_DIR || 'src'
const EXCLUDE = /(node_modules|\/dist\/|\.test\.|\.spec\.|__tests__|__mocks__|\.stories\.|\/prototype\/|\/mock\/|tokens\.)/

// 阈值白名单校验：非数字一律回退默认（配合 execFileSync 双保险）
let fail = false
const threshold = /^\d+(\.\d+)?$/.test(process.env.DUP_THRESHOLD || '') ? process.env.DUP_THRESHOLD : '5'
if (threshold !== (process.env.DUP_THRESHOLD || '5')) console.warn('WARN DUP_THRESHOLD 非法（仅允许数字），已回退为 ' + threshold)

function walk(dir, out = []) {
  if (!existsSync(dir)) return out
  for (const name of readdirSync(dir)) {
    const p = join(dir, name)
    const st = statSync(p)
    if (st.isDirectory()) walk(p, out)
    else if (/\.(tsx|jsx|ts|js|vue|css|scss)$/.test(name) && !EXCLUDE.test(p)) out.push(p)
  }
  return out
}

// ---------- A) 硬编码色值 / 魔法间距 ----------
const hexHits = []
const warnHits = []
const pxHits = []
const HEX_RE = /#[0-9a-fA-F]{3,8}\b/g
const FN_RE = /\brgba?\(|\bhsl\(/g
const ATTR_COLOR_RE = /(fill|stroke)\s*=\s*["']#/

for (const f of walk(join(ROOT, SRC))) {
  const rel = relative(ROOT, f)
  const isCss = /\.(css|scss)$/.test(f)
  const lines = readFileSync(f, 'utf8').split('\n')
  let inBlock = false
  lines.forEach((rawLine, i) => {
    let line = rawLine
    // 块注释状态机：/* ... */ 内容（含跨行）不参与检测
    if (inBlock) {
      const end = line.indexOf('*/')
      if (end === -1) return
      line = line.slice(end + 2)
      inBlock = false
    }
    line = line.replace(/\/\*[^]*?\*\//g, ' ')
    const bs = line.indexOf('/*')
    if (bs !== -1) { line = line.slice(0, bs); inBlock = true }
    // 行尾 // 注释剥离（保护 http:// 等协议头）
    const lc = line.replace(/([^:])\/\/.*$/, '$1')
    const trimmed = lc.trim()
    if (/^(\/\/|\*|#)/.test(trimmed) && !isCss) return
    // CSS 选择器行（以 { 或 , 结尾且 # 出现在首个 : 之前）不做色值检测
    const colonIdx = lc.indexOf(':')
    const hexes = []
    for (const m of lc.matchAll(HEX_RE)) {
      if (isCss && (colonIdx === -1 || m.index < colonIdx)) continue // #feed 选择器
      hexes.push(m[0])
    }
    const fn = lc.match(FN_RE) || []
    if (hexes.length || fn.length) {
      const entry = rel + ':' + (i + 1) + '  ' + hexes.concat(fn).join(' ')
      if (!isCss && ATTR_COLOR_RE.test(lc)) warnHits.push(entry + '  (svg 属性色：建议 currentColor/token)')
      else hexHits.push(entry)
    }
    const magic = lc.match(/\b(padding|margin|gap|font-size|border-radius)\s*[:=]\s*['"]?(\d+)px/g) || []
    for (const m of magic) {
      const n = +m.match(/(\d+)px/)[1]
      if (n !== 0) pxHits.push(rel + ':' + (i + 1) + '  ' + m)
    }
  })
}

if (hexHits.length) {
  console.error('FAIL 硬编码色值 ' + hexHits.length + ' 处（必须改用 design token）:')
  for (const h of hexHits.slice(0, 25)) console.error('    ' + h)
  if (hexHits.length > 25) console.error('    … 其余 ' + (hexHits.length - 25) + ' 处')
  fail = true
} else console.log('OK 无硬编码色值')

if (warnHits.length) {
  console.warn('WARN svg 属性色 ' + warnHits.length + ' 处（不阻断；建议 currentColor 或 token 变量）:')
  for (const h of warnHits.slice(0, 10)) console.warn('    ' + h)
}
if (pxHits.length) {
  console.error('WARN 疑似魔法像素间距 ' + pxHits.length + ' 处（若 token 阶梯中无对应值，应提 CONTRACT_REQUEST 新增 token）:')
  for (const h of pxHits.slice(0, 15)) console.error('    ' + h)
  if (pxHits.length > 15) console.error('    … 其余 ' + (pxHits.length - 15) + ' 处')
}

// ---------- B) 跨文件重复块（依赖 jscpd；execFileSync 数组传参防注入） ----------
const hasJscpd = (() => {
  try { execFileSync('npx', ['--no-install', 'jscpd', '--version'], { stdio: 'ignore' }); return true } catch { return false }
})()
if (hasJscpd) {
  try {
    execFileSync('npx', ['jscpd', SRC, '--min-lines', '8', '--min-tokens', '60', '--reporters', 'consoleFull', '--threshold', threshold, '--silent'], { stdio: 'inherit' })
    console.log('OK 重复块在阈值内')
  } catch {
    console.error('FAIL 重复代码超过阈值 ' + threshold + '%（jscpd 报告见上）')
    console.error('    → Integrator 需据此产出「抽象候选清单」，区分本轮抽取 / 下轮抽取')
    fail = true
  }
} else {
  console.log('SKIP 未安装 jscpd，跳过跨文件重复块检测')
  console.log('     pnpm add -D jscpd   # 并行开发建议必装；A 部分已覆盖最容易失控的样式重复')
}

process.exit(fail ? 1 : 0)
