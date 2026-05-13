import { dirname } from 'path';
import RunCommandAction from './RunCommandAction.js';

export default class RunScriptAction extends RunCommandAction {
  buildCommand() {
    const script = this.settings.script || '';
    if (!script) return '';

    const safeScript = script.replace(/'/g, "'\\''");
    const args = this.settings.args || '';
    const safeArgs = args
      .split(/\s+/)
      .filter(Boolean)
      .map((a) => `'${a.replace(/'/g, "'\\''")}'`)
      .join(' ');
    return safeArgs ? `'${safeScript}' ${safeArgs}` : `'${safeScript}'`;
  }

  async execute() {
    if (!this.settings.cwd && this.settings.script) {
      this.settings.cwd = dirname(this.settings.script);
    }
    return super.execute();
  }
}
