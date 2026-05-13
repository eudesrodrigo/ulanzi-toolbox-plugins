import { executeInITerm } from './iterm-executor.js';
import { executeInTerminalApp } from './terminal-executor.js';
import { getTerminalById } from '../utils/detect-terminal.js';

export async function executeCommand(command, options = {}) {
  const terminal = getTerminalById(options.terminalId);

  if (terminal.id === 'iterm') {
    return executeInITerm(command, options);
  }
  return executeInTerminalApp(command, options);
}
