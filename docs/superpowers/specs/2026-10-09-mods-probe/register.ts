const OUT = '/private/tmp/claude-501/-Users-jason-dev-dotfiles/602de101-f321-414b-b91c-52bd4682857b/scratchpad/probe-out.jsonl'
const shape = (v: unknown, depth = 0): unknown => {
  if (v === null || typeof v !== 'object') return typeof v === 'string' ? `str(${(v as string).length})` : typeof v
  if (Array.isArray(v)) return depth > 2 ? `array(${v.length})` : [v.length, v.length ? shape(v[0], depth + 1) : null]
  if (depth > 3) return 'object'
  return Object.fromEntries(Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, shape(x, depth + 1)]))
}
async function log($: any, row: Record<string, unknown>) {
  const line = JSON.stringify({ t: Date.now(), ...row }) + '\n'
  try {
    const prev = (await $.fs.exists(OUT)) ? await $.fs.read(OUT) : ''
    await $.fs.write(OUT, prev + line)
  } catch (err: any) {
    await $.process.run(['sh', '-c', 'printf "%s" "$1" >> "$2"', 'x', line, OUT])
  }
}
async function tool_call($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'tool.call', keys: Object.keys(e), shape: shape(e), ms: Date.now() - t0, resultShape: shape(r) })
  return r
}
async function tool_check($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'tool.check', keys: Object.keys(e), shape: shape(e), ms: Date.now() - t0, resultShape: shape(r) })
  return r
}
async function turn_start($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'turn.start', keys: Object.keys(e), shape: shape(e), ms: Date.now() - t0, resultShape: shape(r) })
  return r
}
async function turn_complete($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'turn.complete', keys: Object.keys(e), shape: shape(e), ms: Date.now() - t0, resultShape: shape(r) })
  return r
}
async function agent_spawn($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'agent.spawn', keys: Object.keys(e), shape: shape(e), ms: Date.now() - t0, resultShape: shape(r) })
  return r
}
async function session_measure($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'session.measure', keys: Object.keys(e), shape: shape(e), ms: Date.now() - t0, resultShape: shape(r) })
  return r
}
async function c_UserPromptSubmit($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'classic.UserPromptSubmit', keys: Object.keys(e), ms: Date.now() - t0, resultShape: shape(r), resultChars: JSON.stringify(r ?? null).length, resultSample: JSON.stringify(r ?? null).slice(0, 600) })
  return r
}
async function c_PreToolUse($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'classic.PreToolUse', keys: Object.keys(e), ms: Date.now() - t0, resultShape: shape(r), resultChars: JSON.stringify(r ?? null).length, resultSample: JSON.stringify(r ?? null).slice(0, 600) })
  return r
}
async function c_PostToolUse($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'classic.PostToolUse', keys: Object.keys(e), ms: Date.now() - t0, resultShape: shape(r), resultChars: JSON.stringify(r ?? null).length, resultSample: JSON.stringify(r ?? null).slice(0, 600) })
  return r
}
async function c_SessionStart($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'classic.SessionStart', keys: Object.keys(e), ms: Date.now() - t0, resultShape: shape(r), resultChars: JSON.stringify(r ?? null).length, resultSample: JSON.stringify(r ?? null).slice(0, 600) })
  return r
}
async function c_Stop($: any, e: any, next: any) {
  const t0 = Date.now()
  const r = await next(e)
  await log($, { ev: 'classic.Stop', keys: Object.keys(e), ms: Date.now() - t0, resultShape: shape(r), resultChars: JSON.stringify(r ?? null).length, resultSample: JSON.stringify(r ?? null).slice(0, 600) })
  return r
}
async function* turn_step($: any, e: any, next: any) {
  await log($, { ev: 'turn.step', keys: Object.keys(e), shape: shape(e) })
  yield* next(e)
}
async function prompt_compose($: any, e: any, next: any) {
  const r = await next(e)
  const sections = (r?.sections ?? []).map((s: any) => ({ id: s.id, scope: s.scope, chars: (s.text ?? '').length }))
  await log($, { ev: 'prompt.compose', keys: Object.keys(e), sections, total: sections.reduce((a: number, s: any) => a + s.chars, 0) })
  return r
}
async function prompt_context($: any, e: any, next: any) {
  const r = await next(e)
  await log($, { ev: 'prompt.context', keys: Object.keys(e), shape: shape(e), resultShape: shape(r), blocks: (r?.blocks ?? []).map((b: any) => ({ keys: Object.keys(b), chars: JSON.stringify(b).length })) })
  return r
}
async function prompt_attachment($: any, e: any, next: any) {
  const r = await next(e)
  await log($, { ev: 'prompt.attachment', type: e.type, keys: Object.keys(e), chars: (r?.text ?? '').length })
  return r
}
async function session_start($: any, e: any, next: any) {
  let usage, model, surfaces, version
  try { usage = await $.session.usage() } catch (err: any) { usage = 'err ' + err?.message }
  try { model = await $.session.model() } catch (err: any) { model = 'err ' + err?.message }
  try { surfaces = await $.session.surfaces() } catch (err: any) { surfaces = 'err ' + err?.message }
  try { version = await $.session.version() } catch (err: any) { version = 'err ' + err?.message }
  await log($, { ev: 'session.start', keys: Object.keys(e), usage, model, surfaces, version, pluginRoot: $.plugin.root })
  return next(e)
}
export function register(on: any) {
  on('tool.call', tool_call).catch(() => {})
  on('tool.check', tool_check).catch(() => {})
  on('turn.start', turn_start).catch(() => {})
  on('turn.complete', turn_complete).catch(() => {})
  on('agent.spawn', agent_spawn).catch(() => {})
  on('session.measure', session_measure).catch(() => {})
  on('classic.UserPromptSubmit', c_UserPromptSubmit).catch(() => {})
  on('classic.PreToolUse', c_PreToolUse).catch(() => {})
  on('classic.PostToolUse', c_PostToolUse).catch(() => {})
  on('classic.SessionStart', c_SessionStart).catch(() => {})
  on('classic.Stop', c_Stop).catch(() => {})
  on('turn.step', turn_step)
  on('prompt.compose', prompt_compose).catch(() => {})
  on('prompt.context', prompt_context).catch(() => {})
  on('prompt.attachment', prompt_attachment).catch(() => {})
  on('session.start', session_start)
}
