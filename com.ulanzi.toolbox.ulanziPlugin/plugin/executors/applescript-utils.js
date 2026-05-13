import { execFile } from 'child_process';

export function escapeAppleScript(str) {
  return str.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

export function buildFullCommand(command, { cwd, exitFile }) {
  const cdPart = cwd ? `cd '${cwd.replace(/'/g, "'\\''")}' && ` : '';
  const exitCapture = exitFile ? `; echo $? > '${exitFile.replace(/'/g, "'\\''")}'` : '';
  return `${cdPart}${command}${exitCapture}`;
}

export const SHELL_INIT = 'unsetopt BANG_HIST 2>/dev/null; set +H 2>/dev/null';

export function runAppleScript(script) {
  return new Promise((resolve, reject) => {
    execFile('osascript', ['-e', script], (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}
