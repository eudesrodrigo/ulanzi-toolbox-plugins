import {
  escapeAppleScript,
  buildFullCommand,
  SHELL_INIT,
  runAppleScript,
} from './applescript-utils.js';

export function executeInTerminalApp(command, opts) {
  const fullCommand = buildFullCommand(command, opts);
  const label = escapeAppleScript(opts.label || 'Dev Tools');
  const init = escapeAppleScript(SHELL_INIT);
  const cmd = escapeAppleScript(fullCommand);

  return runAppleScript(`
    tell application "Terminal"
      activate
      do script "${init}"
      delay 0.2
      do script "${cmd}" in front window
      set custom title of front window to "${label}"
    end tell
  `);
}
