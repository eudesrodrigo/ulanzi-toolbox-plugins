import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('./applescript-utils.js', () => ({
  escapeAppleScript: vi.fn((s) => s),
  buildFullCommand: vi.fn((cmd) => cmd),
  SHELL_INIT: 'shell-init',
  runAppleScript: vi.fn(() => Promise.resolve()),
}));

import { executeInTerminalApp } from './terminal-executor.js';
import { runAppleScript, buildFullCommand, escapeAppleScript } from './applescript-utils.js';

describe('executeInTerminalApp', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('calls runAppleScript with Terminal tell block', async () => {
    await executeInTerminalApp('npm start', { label: 'Server' });

    expect(buildFullCommand).toHaveBeenCalledWith('npm start', { label: 'Server' });
    expect(runAppleScript).toHaveBeenCalledWith(
      expect.stringContaining('tell application "Terminal"'),
    );
  });

  it('includes the escaped command in the script', async () => {
    await executeInTerminalApp('make build', { label: 'Build' });

    const script = vi.mocked(runAppleScript).mock.calls[0][0];
    expect(script).toContain('do script "make build" in front window');
  });

  it('includes shell init in the script', async () => {
    await executeInTerminalApp('ls', { label: 'List' });

    const script = vi.mocked(runAppleScript).mock.calls[0][0];
    expect(script).toContain('do script "shell-init"');
  });

  it('uses default label when not provided', async () => {
    await executeInTerminalApp('echo hi', {});

    expect(escapeAppleScript).toHaveBeenCalledWith('Dev Tools');
  });

  it('sets the window title', async () => {
    await executeInTerminalApp('cmd', { label: 'MyWindow' });

    const script = vi.mocked(runAppleScript).mock.calls[0][0];
    expect(script).toContain('set custom title of front window to "MyWindow"');
  });
});
