import { exec } from 'child_process';
import { existsSync, readFileSync, unlinkSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { executeCommand } from '../executors/executor.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = resolve(__dirname, '../../scripts/deep-clean.sh');
const POLL_INTERVAL_MS = 200;
const DISK_POLL_INTERVAL_MS = 60000;
const CANVAS_SIZE = 300;

export function parseDiskutilOutput(stdout) {
  const lines = stdout.split('\n');
  let total = null;
  let free = null;
  for (const line of lines) {
    if (line.includes('Container Total Space:')) {
      const match = line.split(':')[1]?.trim().split(' GB')[0];
      if (match) total = parseFloat(match);
    } else if (line.includes('Container Free Space:')) {
      const match = line.split(':')[1]?.trim().split(' GB')[0];
      if (match) free = parseFloat(match);
    }
  }
  if (total === null || free === null || isNaN(total) || isNaN(free)) return null;
  return { free: Math.round(free), total: Math.round(total) };
}

export function generateIdleIcon(free, total) {
  const pct = total > 0 ? Math.round(((total - free) / total) * 100) : 0;
  const barWidth = 220;
  const filled = Math.round((pct / 100) * barWidth);
  const barColor = pct >= 90 ? '#ff4444' : pct >= 75 ? '#ffaa00' : '#00FFE6';
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CANVAS_SIZE} ${CANVAS_SIZE}">
  <rect width="${CANVAS_SIZE}" height="${CANVAS_SIZE}" fill="#1e1f22"/>
  <text x="150" y="80" text-anchor="middle" font-family="Arial,sans-serif" font-size="32" fill="#888">${pct}% used</text>
  <rect x="40" y="100" width="${barWidth}" height="18" rx="9" fill="#333"/>
  <rect x="40" y="100" width="${filled}" height="18" rx="9" fill="${barColor}"/>
  <text x="150" y="190" text-anchor="middle" font-family="Arial,sans-serif" font-size="56" font-weight="bold" fill="#fff">${free}/${total}</text>
  <text x="150" y="245" text-anchor="middle" font-family="Arial,sans-serif" font-size="38" fill="#00FFE6">GB</text>
</svg>`;
  return 'data:image/svg+xml;base64,' + Buffer.from(svg, 'utf8').toString('base64');
}

export function generateRunningIcon() {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CANVAS_SIZE} ${CANVAS_SIZE}">
  <rect width="${CANVAS_SIZE}" height="${CANVAS_SIZE}" fill="#1e1f22"/>
  <text x="150" y="120" text-anchor="middle" font-family="Arial,sans-serif" font-size="30" fill="#888">cleaning</text>
  <circle cx="110" cy="175" r="12" fill="#00FFE6" opacity="0.3"/>
  <circle cx="150" cy="175" r="12" fill="#00FFE6" opacity="0.6"/>
  <circle cx="190" cy="175" r="12" fill="#00FFE6"/>
  <text x="150" y="250" text-anchor="middle" font-family="Arial,sans-serif" font-size="26" fill="#555">please wait</text>
</svg>`;
  return 'data:image/svg+xml;base64,' + Buffer.from(svg, 'utf8').toString('base64');
}

export default class DeepCleanAction {
  constructor(context, $UD) {
    this.context = context;
    this.$UD = $UD;
    this.settings = {};
    this.active = true;
    this.running = false;
    this.timer = null;
  }

  updateSettings(settings) {
    Object.assign(this.settings, settings);
  }

  onAppear() {
    this.refreshDiskDisplay();
    this.startPolling();
  }

  onDisappear() {
    this.stopPolling();
  }

  onActiveChange(active) {
    if (active) {
      this.refreshDiskDisplay();
      this.startPolling();
    } else {
      this.stopPolling();
    }
  }

  startPolling() {
    this.stopPolling();
    this.timer = setInterval(() => {
      if (!this.running) this.refreshDiskDisplay();
    }, DISK_POLL_INTERVAL_MS);
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  refreshDiskDisplay() {
    this.getDiskUsage((usage) => {
      if (usage) {
        this.$UD.setBaseDataIcon(this.context, generateIdleIcon(usage.free, usage.total));
      }
    });
  }

  getDiskUsage(callback) {
    exec('diskutil info /', (err, stdout) => {
      if (err) {
        callback(null);
        return;
      }
      callback(parseDiskutilOutput(stdout));
    });
  }

  buildCommand() {
    return `'${SCRIPT_PATH.replace(/'/g, "'\\''")}'`;
  }

  async execute() {
    if (this.running) return;
    this.running = true;
    this.stopPolling();

    this.$UD.setBaseDataIcon(this.context, generateRunningIcon());

    const exitFile = join(
      tmpdir(),
      `ulanzi-exit-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    );

    const command = this.buildCommand();
    const opts = {
      label: 'Deep Clean',
      terminalId: this.settings.terminal,
      exitFile,
    };

    try {
      await executeCommand(command, opts);
      this.pollExitCode(exitFile);
    } catch {
      this.onScriptDone('1');
    }
  }

  pollExitCode(exitFile) {
    const poll = () => {
      if (!this.active) {
        this.onScriptDone('2');
        return;
      }

      if (existsSync(exitFile)) {
        let exitCode = '0';
        try {
          exitCode = readFileSync(exitFile, 'utf-8').trim();
          unlinkSync(exitFile);
        } catch {
          // TOCTOU: file may have been removed between check and read
        }
        this.onScriptDone(exitCode);
        return;
      }

      setTimeout(poll, POLL_INTERVAL_MS);
    };

    setTimeout(poll, POLL_INTERVAL_MS);
  }

  onScriptDone(exitCode) {
    this.running = false;

    if (exitCode === '1') {
      this.$UD.showAlert(this.context);
    }

    this.refreshDiskDisplay();
    this.startPolling();
  }
}
