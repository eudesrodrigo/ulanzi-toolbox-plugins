import { existsSync, readFileSync, unlinkSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { executeCommand } from '../executors/executor.js';

const EXIT_POLL_INTERVAL_MS = 200;
const EXIT_POLL_TIMEOUT_MS = 30000;

export default class RunCommandAction {
  constructor(context, $UD) {
    this.context = context;
    this.$UD = $UD;
    this.settings = {};
    this.active = true;
  }

  updateSettings(settings) {
    Object.assign(this.settings, settings);
  }

  buildCommand() {
    return this.settings.command || '';
  }

  async execute() {
    const command = this.buildCommand();
    if (!command) {
      this.$UD.showAlert(this.context);
      return;
    }

    const exitFile = join(
      tmpdir(),
      `ulanzi-exit-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    );

    try {
      await executeCommand(command, {
        label: this.settings.label,
        cwd: this.settings.cwd,
        terminalId: this.settings.terminal,
        exitFile,
      });
      this.pollExitCode(exitFile);
    } catch {
      this.$UD.showAlert(this.context);
    }
  }

  pollExitCode(exitFile) {
    const startTime = Date.now();

    const poll = () => {
      if (!this.active) return;

      if (existsSync(exitFile)) {
        try {
          readFileSync(exitFile, 'utf-8');
          unlinkSync(exitFile);
        } catch {
          // exit file may have been removed between existsSync and read
        }
        return;
      }

      if (Date.now() - startTime > EXIT_POLL_TIMEOUT_MS) return;

      setTimeout(poll, EXIT_POLL_INTERVAL_MS);
    };

    setTimeout(poll, EXIT_POLL_INTERVAL_MS);
  }
}
