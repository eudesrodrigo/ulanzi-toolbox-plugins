import { dirname } from 'path';
import RunCommandAction from './RunCommandAction.js';

export default class RunScriptAction extends RunCommandAction {
  buildCommand() {
    const script = this.settings.script || '';
    if (!script) return '';

    const args = this.settings.args || '';
    const safeScript = script.replace(/'/g, "'\\''");
    return args ? `'${safeScript}' ${args}` : `'${safeScript}'`;
  }

  async execute() {
    if (!this.settings.cwd && this.settings.script) {
      this.settings.cwd = dirname(this.settings.script);
    }
    return super.execute();
  }
}
