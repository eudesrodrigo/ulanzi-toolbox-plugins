import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('child_process', () => ({
  execFile: vi.fn(),
}));

import {
  escapeAppleScript,
  buildFullCommand,
  SHELL_INIT,
  runAppleScript,
} from './applescript-utils.js';
import { execFile } from 'child_process';

describe('escapeAppleScript', () => {
  it('escapes backslashes', () => {
    expect(escapeAppleScript('path\\to\\file')).toBe('path\\\\to\\\\file');
  });

  it('escapes double quotes', () => {
    expect(escapeAppleScript('say "hello"')).toBe('say \\"hello\\"');
  });

  it('escapes both backslashes and quotes', () => {
    expect(escapeAppleScript('echo "C:\\Users"')).toBe('echo \\"C:\\\\Users\\"');
  });

  it('returns empty string unchanged', () => {
    expect(escapeAppleScript('')).toBe('');
  });

  it('leaves safe characters untouched', () => {
    expect(escapeAppleScript('ls -la /tmp')).toBe('ls -la /tmp');
  });
});

describe('buildFullCommand', () => {
  it('returns command as-is when no options', () => {
    expect(buildFullCommand('echo hi', {})).toBe('echo hi');
  });

  it('prepends cd when cwd is provided', () => {
    const result = buildFullCommand('make build', { cwd: '/home/user/project' });
    expect(result).toBe("cd '/home/user/project' && make build");
  });

  it('escapes single quotes in cwd', () => {
    const result = buildFullCommand('ls', { cwd: "/path/with'quote" });
    expect(result).toBe("cd '/path/with'\\''quote' && ls");
  });

  it('appends exit code capture when exitFile is provided', () => {
    const result = buildFullCommand('npm test', { exitFile: '/tmp/exit-123' });
    expect(result).toBe("npm test; echo $? > '/tmp/exit-123'");
  });

  it('combines cwd and exitFile', () => {
    const result = buildFullCommand('go build', {
      cwd: '/project',
      exitFile: '/tmp/exit',
    });
    expect(result).toBe("cd '/project' && go build; echo $? > '/tmp/exit'");
  });

  it('escapes single quotes in exitFile', () => {
    const result = buildFullCommand('cmd', { exitFile: "/tmp/it's" });
    expect(result).toBe("cmd; echo $? > '/tmp/it'\\''s'");
  });
});

describe('SHELL_INIT', () => {
  it('disables bang history for both zsh and bash', () => {
    expect(SHELL_INIT).toContain('unsetopt BANG_HIST');
    expect(SHELL_INIT).toContain('set +H');
  });
});

describe('runAppleScript', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('resolves when osascript succeeds', async () => {
    vi.mocked(execFile).mockImplementation((_cmd, _args, cb) => cb(null));

    await expect(runAppleScript('tell app "Finder" to activate')).resolves.toBeUndefined();
    expect(execFile).toHaveBeenCalledWith(
      'osascript',
      ['-e', 'tell app "Finder" to activate'],
      expect.any(Function),
    );
  });

  it('rejects when osascript fails', async () => {
    const error = new Error('osascript: syntax error');
    vi.mocked(execFile).mockImplementation((_cmd, _args, cb) => cb(error));

    await expect(runAppleScript('bad script')).rejects.toThrow('osascript: syntax error');
  });
});
