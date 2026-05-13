import {
  escapeAppleScript,
  buildFullCommand,
  SHELL_INIT,
  runAppleScript,
} from './applescript-utils.js';

export function executeInITerm(command, opts) {
  const fullCommand = buildFullCommand(command, opts);
  const label = escapeAppleScript(opts.label || 'Dev Tools');
  const init = escapeAppleScript(SHELL_INIT);
  const cmd = escapeAppleScript(fullCommand);

  return runAppleScript(`
    tell application "iTerm"
      activate
      if (count of windows) = 0 then
        create window with default profile
        tell current session of current window
          set name to "${label}"
          write text "${init}"
          write text "${cmd}"
        end tell
      else
        tell current window
          create tab with default profile
          tell current session
            set name to "${label}"
            write text "${init}"
            write text "${cmd}"
          end tell
        end tell
      end if
    end tell
  `);
}
