import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('./applescript-utils.js', () => ({
  escapeAppleScript: vi.fn((s) => s),
  buildFullCommand: vi.fn((cmd) => cmd),
  SHELL_INIT: 'shell-init',
  runAppleScript: vi.fn(() => Promise.resolve()),
}));

import { executeInITerm } from './iterm-executor.js';
import { runAppleScript, buildFullCommand, escapeAppleScript } from './applescript-utils.js';

describe('executeInITerm', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('calls runAppleScript with iTerm tell block', async () => {
    await executeInITerm('npm test', { label: 'Tests' });

    expect(buildFullCommand).toHaveBeenCalledWith('npm test', { label: 'Tests' });
    expect(escapeAppleScript).toHaveBeenCalledWith('Tests');
    expect(runAppleScript).toHaveBeenCalledWith(
      expect.stringContaining('tell application "iTerm"'),
    );
  });

  it('includes the escaped command in the script', async () => {
    await executeInITerm('make build', { label: 'Build' });

    const script = vi.mocked(runAppleScript).mock.calls[0][0];
    expect(script).toContain('write text "make build"');
  });

  it('includes shell init in the script', async () => {
    await executeInITerm('ls', { label: 'List' });

    const script = vi.mocked(runAppleScript).mock.calls[0][0];
    expect(script).toContain('write text "shell-init"');
  });

  it('uses default label when not provided', async () => {
    await executeInITerm('echo hi', {});

    expect(escapeAppleScript).toHaveBeenCalledWith('Dev Tools');
  });

  it('sets the session name', async () => {
    await executeInITerm('cmd', { label: 'MyTab' });

    const script = vi.mocked(runAppleScript).mock.calls[0][0];
    expect(script).toContain('set name to "MyTab"');
  });
});
