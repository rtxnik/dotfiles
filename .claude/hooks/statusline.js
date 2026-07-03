#!/usr/bin/env node
// Workspace Statusline — 3 Zone Adaptive (Gruvbox Dark)
// ┌──────────┐ ┌──────────────────────┐ ┌─────────────────┐
// │  WHERE   │ │  RESOURCE (escalates)│ │    ACTIVITY     │
// └──────────┘ └──────────────────────┘ └─────────────────┘
// Resource zone grows with urgency. Line length = health indicator.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

// ── Gruvbox Dark ──────────────────────────────────────────────────
const C = {
  fg:     '\x1b[38;2;235;219;178m',
  red:    '\x1b[38;2;251;73;52m',
  green:  '\x1b[38;2;184;187;38m',
  yellow: '\x1b[38;2;250;189;47m',
  blue:   '\x1b[38;2;131;165;152m',
  purple: '\x1b[38;2;211;134;155m',
  aqua:   '\x1b[38;2;142;192;124m',
  orange: '\x1b[38;2;254;128;25m',
  gray:   '\x1b[38;2;146;131;116m',
  bold:   '\x1b[1m',
  dim:    '\x1b[2m',
  blink:  '\x1b[5m',
  reset:  '\x1b[0m',
};
const SEP = ` ${C.gray}\u2502${C.reset} `;

// ── Urgency levels ────────────────────────────────────────────────
const CALM = 0;     // ctx <40%
const NORMAL = 1;   // ctx 40-59%
const WARNING = 2;  // ctx 60-79%
const CRITICAL = 3; // ctx 80%+

// ── Helpers ───────────────────────────────────────────────────────
function sh(cmd) {
  try {
    return execSync(cmd, { timeout: 2000, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
  } catch { return ''; }
}

// Single shell call for all git data (7 commands → 1 exec)
function gitSnapshot() {
  const script = [
    'git rev-parse --abbrev-ref HEAD 2>/dev/null',
    'git status --porcelain 2>/dev/null',
    'git rev-list --count @{u}..HEAD 2>/dev/null || echo 0',
    'git rev-list --count HEAD..@{u} 2>/dev/null || echo 0',
    'git stash list 2>/dev/null | wc -l',
    'git log -1 --format=%ct 2>/dev/null',
    'git rev-parse --git-dir 2>/dev/null',
  ].join(' && echo "---GIT_SEP---" && ');
  const raw = sh(script);
  if (!raw) return null;
  const parts = raw.split('---GIT_SEP---').map(s => s.trim());
  return {
    branch: parts[0] || '',
    porcelain: parts[1] || '',
    ahead: parseInt(parts[2], 10) || 0,
    behind: parseInt(parts[3], 10) || 0,
    stashCount: parseInt(parts[4], 10) || 0,
    lastCommitEpoch: parseInt(parts[5], 10) || 0,
    gitDir: parts[6] || '',
  };
}

function readFile(fp) {
  try { return fs.readFileSync(fp, 'utf8'); } catch { return ''; }
}

function fileAge(fp) {
  try { return Date.now() - fs.statSync(fp).mtimeMs; } catch { return Infinity; }
}

function getUrgency(usedPct) {
  if (usedPct >= 80) return CRITICAL;
  if (usedPct >= 60) return WARNING;
  if (usedPct >= 40) return NORMAL;
  return CALM;
}

// Visible length (strip ANSI)
function visLen(s) {
  return s.replace(/\x1b\[[0-9;]*m/g, '').replace(/\ud83d\udc80/g, 'XX').length;
}

// Context pie: single char = instant read
function pie(pct) {
  if (pct < 10) return '\u25cb';   // ○
  if (pct < 35) return '\u25d4';   // ◔
  if (pct < 60) return '\u25d1';   // ◑
  if (pct < 80) return '\u25d5';   // ◕
  return '\u25cf';                  // ●
}

// Shorten branch for CRITICAL
function shortenBranch(branch) {
  let s = branch.replace(/^feat\//, '').replace(/^fix\//, '').replace(/phase-/, 'p');
  if (s.length > 8) s = s.replace(/^(p\d+-)(\w{2}).*/, '$1$2');
  return s;
}

// Format duration: ms → "14m" / "1h23m"
function fmtDuration(ms) {
  if (ms == null || ms <= 0) return '';
  const mins = Math.floor(ms / 60000);
  if (mins < 1) return '';
  if (mins < 60) return `${mins}m`;
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return m > 0 ? `${h}h${m}m` : `${h}h`;
}

// Format countdown: epoch → "↻2h" / "↻45m"
function fmtCountdown(epochSec) {
  if (epochSec == null) return '';
  const diff = epochSec * 1000 - Date.now();
  if (diff <= 0) return '';
  const mins = Math.floor(diff / 60000);
  if (mins >= 60) return `\u21bb${Math.floor(mins / 60)}h`;
  return `\u21bb${mins}m`;
}

// Context trend: compare current to previous, return arrow
function ctxTrend(session, currentUsed) {
  if (!session) return '';
  const safe = String(session).replace(/[^A-Za-z0-9._-]/g, '_').replace(/\.\.+/g, '_');
  const trendFile = path.join(os.tmpdir(), `claude-ctx-trend-${safe}.json`);
  let prev = [];
  try { prev = JSON.parse(readFile(trendFile)) || []; } catch {}
  if (!Array.isArray(prev)) prev = [];

  prev.push(currentUsed);
  if (prev.length > 5) prev = prev.slice(-5);
  try { fs.writeFileSync(trendFile, JSON.stringify(prev)); } catch {}

  if (prev.length < 2) return '';
  const delta = currentUsed - prev[0];
  if (delta >= 10) return '\u2197';  // ↗ fast
  if (delta >= 3) return '\u2192';   // → steady
  if (delta <= -3) return '\u2198';  // ↘ shrinking (after compact)
  return '';
}

// Branch color by last commit age
function branchAgeColor(isDefault, lastCommitEpoch) {
  if (isDefault) return `${C.bold}${C.red}`;
  if (!lastCommitEpoch) return C.green;
  const ageMins = (Date.now() / 1000 - lastCommitEpoch) / 60;
  if (ageMins < 60) return C.green;
  if (ageMins < 360) return C.yellow;
  return C.orange;
}

// Shorten model name: "Claude Opus 4.6 (1M context)" → "Opus 4.6 1M"
function shortenModel(raw) {
  if (!raw) return '';
  const m = raw.match(/(Opus|Sonnet|Haiku)\s*(\d+\.\d+)/i);
  if (!m) return raw.length > 15 ? raw.substring(0, 15) : raw;
  const suffix = /\b1[Mm]\b/.test(raw) ? ' 1M' : '';
  return `${m[1]} ${m[2]}${suffix}`;
}

// ── Main ──────────────────────────────────────────────────────────
let input = '';
const guard = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  clearTimeout(guard);
  try {
    const data = JSON.parse(input);
    const dir = data.workspace?.current_dir || process.cwd();
    const session = data.session_id || '';
    const remaining = data.context_window?.remaining_percentage;
    const projectName = path.basename(dir);
    const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');

    // ── Calculate context used % ──────────────────────
    const BUFFER = 16.5;
    let used = 0;
    if (remaining != null) {
      const usable = Math.max(0, ((remaining - BUFFER) / (100 - BUFFER)) * 100);
      used = Math.max(0, Math.min(100, Math.round(100 - usable)));
    }
    const level = remaining != null ? getUrgency(used) : CALM;

    // Bridge for context-exhaustion-gate hook (B3). Sanitize the FILENAME only
    // (collapse dot-runs so no literal '..' survives); keep the RAW session_id in the
    // CONTENT so the consumer's .session_id match holds. Atomic write (temp + rename)
    // so a torn read never yields half a file.
    if (session && remaining != null) {
      try {
        const safe = String(session).replace(/[^A-Za-z0-9._-]/g, '_').replace(/\.\.+/g, '_');
        const dest = path.join(os.tmpdir(), `claude-ctx-${safe}.json`);
        const tmp = `${dest}.tmp.${process.pid}`;
        fs.writeFileSync(tmp, JSON.stringify({ session_id: session, remaining_percentage: remaining, used_pct: used, ts: Date.now() }));
        fs.renameSync(tmp, dest);
      } catch {}
    }

    // ══════════════════════════════════════════════════
    // ZONE 1: WHERE
    // ══════════════════════════════════════════════════
    let where = '';
    const git = gitSnapshot();
    const branch = git?.branch || '';
    {
      if (branch) {
        const dirty = git.porcelain ? git.porcelain.split('\n').filter(Boolean).length : 0;

        const isDefault = branch === 'main' || branch === 'master';
        const display = level >= CRITICAL ? shortenBranch(branch) : branch;
        const branchColor = branchAgeColor(isDefault, git.lastCommitEpoch);

        where = `${C.bold}${C.blue}${projectName}${C.reset} ${branchColor}${display}${C.reset}`;
        if (dirty > 0) where += ` ${C.yellow}\u25cf ${dirty}${C.reset}`;
        if (git.ahead > 0) where += ` ${C.green}\u2191 ${git.ahead}${C.reset}`;
        if (git.behind > 0) where += ` ${C.red}\u2193 ${git.behind}${C.reset}`;

        if (git.stashCount > 0) where += ` ${C.purple}\u2261 ${git.stashCount}${C.reset}`;

        if (git.porcelain && /^U.|.U|^AA|^DD/m.test(git.porcelain)) {
          where += ` ${C.red}\u2716 conflict${C.reset}`;
        }

        if (git.gitDir && git.gitDir.includes('worktrees')) {
          where += ` ${C.orange}\u2442${C.reset}`;
        }
      } else {
        where = `${C.bold}${C.blue}${projectName}${C.reset}`;
      }

      // Workflow phase from integration fabric state file
      {
        const projectDir = process.env.CLAUDE_PROJECT_DIR || dir;
        // Resolve .planning the same way hooklib.sh planning_dir() does: git root, else project dir.
        let planningRoot = projectDir;
        try {
          planningRoot = execSync('git rev-parse --show-toplevel', { cwd: projectDir, stdio: ['ignore', 'pipe', 'ignore'] })
            .toString().trim() || projectDir;
        } catch (e) { /* not a git repo: keep projectDir */ }
        const wsPath = path.join(planningRoot, '.planning', 'workflow-state.json');
        const stateRaw = readFile(wsPath);
        if (stateRaw) {
          try {
            const ws = JSON.parse(stateRaw);
            if (ws.phase && ws.phase !== 'idle') {
              const phaseIcons = {
                designing: `${C.blue}✎`,
                planning: `${C.purple}☰`,
                executing: `${C.green}⚙`,
                reviewing: `${C.yellow}⚑`,
                complete: `${C.aqua}✓`,
              };
              const icon = phaseIcons[ws.phase] || `${C.gray}${ws.phase}`;
              const maxLen = level >= CRITICAL ? 6 : 12;
              const label = ws.phase.length > maxLen ? ws.phase.substring(0, maxLen) : ws.phase;
              where += `${SEP}${icon} ${label}${C.reset}`;
            }
          } catch {}
        }
      }
    }

    // ══════════════════════════════════════════════════
    // ZONE 2: RESOURCE
    // ══════════════════════════════════════════════════
    let resource = '';
    {
      const cost = data.cost?.total_cost_usd;
      const duration = data.cost?.total_duration_ms;
      const rl5h = data.rate_limits?.five_hour;
      const rl7d = data.rate_limits?.seven_day;

      let ctxColor = C.aqua;
      if (level === NORMAL) ctxColor = C.yellow;
      else if (level === WARNING) ctxColor = C.orange;
      else if (level === CRITICAL) ctxColor = `${C.blink}${C.red}`;

      if (remaining != null) {
        const icon = level >= CRITICAL ? '\ud83d\udc80' : pie(used);
        const trend = ctxTrend(session, used);
        const trendStr = trend ? `${C.gray}${trend}${C.reset}` : '';
        const spacer = resource ? '  ' : '';
        resource += `${spacer}${ctxColor}${icon} ${used}%${C.reset}${trendStr}`;
      }

      const isExtraUsage = (rl5h != null && rl5h.used_percentage >= 100)
        || (rl7d != null && rl7d.used_percentage >= 100);
      if (isExtraUsage && cost != null && cost > 0) {
        resource += `  ${C.red}$${cost.toFixed(2)}${C.reset}`;
      }

      if (level >= WARNING && rl5h != null) {
        const rl5pct = Math.round(rl5h.used_percentage);
        const rlColor = rl5pct >= 100 ? `${C.blink}${C.red}` : rl5pct >= 80 ? C.red : rl5pct >= 50 ? C.orange : C.yellow;
        const rlPie = rl5pct >= 100 ? '\u25cf' : pie(rl5pct);
        const cd = (level >= CRITICAL && !isExtraUsage) ? fmtCountdown(rl5h.resets_at) : '';
        resource += `  ${C.dim}5h${C.reset} ${rlColor}${rlPie}${C.reset}`;
        if (cd) resource += ` ${C.gray}${cd}${C.reset}`;
      }

      if (level >= CRITICAL && rl7d != null) {
        const rl7pct = Math.round(rl7d.used_percentage);
        const rlColor = rl7pct >= 100 ? `${C.blink}${C.red}` : rl7pct >= 80 ? C.red : C.orange;
        const rlPie = rl7pct >= 100 ? '\u25cf' : pie(rl7pct);
        const cd = !isExtraUsage ? fmtCountdown(rl7d.resets_at) : '';
        resource += `  ${C.dim}7d${C.reset} ${rlColor}${rlPie}${C.reset}`;
        if (cd) resource += ` ${C.gray}${cd}${C.reset}`;
      }

      if (level < WARNING) {
        const dur = fmtDuration(duration);
        if (dur) resource += `  ${C.gray}\u25f7 ${dur}${C.reset}`;
      }
    }

    // ══════════════════════════════════════════════════
    // ZONE 3: ACTIVITY
    // ══════════════════════════════════════════════════
    let activity = '';
    {
      let tools = '';
      const counterFile = path.join(os.tmpdir(), `${projectName}-tool-counter`);
      if (fileAge(counterFile) < 7200000) {
        try {
          const count = parseInt(fs.readFileSync(counterFile, 'utf8').trim(), 10);
          if (!isNaN(count) && count > 0) {
            let color = C.dim;
            if (count >= 45) color = C.red;
            else if (count >= 35) color = C.orange;
            else if (count >= 25) color = C.yellow;
            tools = `${color}\u26a1${count}${C.reset}`;
          }
        } catch {}
      }
      const toolsVisLen = tools ? visLen(tools) + 2 : 0;

      let task = '';
      if (session) {
        const usedWidth = visLen(where) + 3 + visLen(resource) + 3 + toolsVisLen;
        const maxLen = Math.max(0, 80 - usedWidth - 3);
        if (maxLen >= 8) {
          const todosDir = path.join(claudeDir, 'todos');
          try {
            if (fs.existsSync(todosDir)) {
              const files = fs.readdirSync(todosDir)
                .filter(f => f.startsWith(session) && f.endsWith('.json'))
                .sort((a, b) => {
                  try {
                    return fs.statSync(path.join(todosDir, b)).mtimeMs -
                           fs.statSync(path.join(todosDir, a)).mtimeMs;
                  } catch { return 0; }
                });
              for (const file of files) {
                try {
                  const todos = JSON.parse(fs.readFileSync(path.join(todosDir, file), 'utf8'));
                  const ip = (Array.isArray(todos) ? todos : []).find(t => t.status === 'in_progress');
                  if (ip) {
                    const raw = ip.content || ip.activeForm || '';
                    task = raw.length > maxLen ? raw.substring(0, maxLen - 1) + '\u2026' : raw;
                    break;
                  }
                } catch {}
              }
            }
          } catch {}
        }
      }

      if (task && tools) activity = `${C.fg}${task}${C.reset}  ${tools}`;
      else if (task) activity = `${C.fg}${task}${C.reset}`;
      else if (tools) activity = tools;
    }

    let prefix = ''
    const model = shortenModel(data.model?.display_name);
    if (model) prefix += `${C.dim}${model}${C.reset}${SEP}`;

    const zones = [where, resource];
    if (activity) zones.push(activity);

    process.stdout.write(prefix + zones.filter(Boolean).join(SEP));

  } catch {
    // Top-level: never crash, show nothing
  }
});
