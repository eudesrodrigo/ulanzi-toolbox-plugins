import { exec } from 'child_process';
import { existsSync, readFileSync, unlinkSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { executeCommand } from '../executors/executor.js';
import { parseDiskutilOutput, generateIdleIcon, generateRunningIcon } from './DeepCleanAction.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = resolve(__dirname, '../../scripts/ai-clean.sh');
const POLL_INTERVAL_MS = 200;
const DISK_POLL_INTERVAL_MS = 60000;

export default class AICleanAction {
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
      label: 'AI Clean',
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
