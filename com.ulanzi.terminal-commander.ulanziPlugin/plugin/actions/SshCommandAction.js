import RunCommandAction from './RunCommandAction.js';

const VALID_HOST = /^[a-zA-Z0-9._@:-]+$/;

export default class SshCommandAction extends RunCommandAction {
  buildCommand() {
    const host = this.settings.host || '';
    const command = this.settings.command || '';
    if (!host || !command) return '';
    if (!VALID_HOST.test(host)) return '';

    return `ssh ${host} '${command.replace(/'/g, "'\\''")}'`;
  }
}
