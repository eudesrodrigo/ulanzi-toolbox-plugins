import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../executors/executor.js', () => ({
  executeCommand: vi.fn(() => Promise.resolve()),
}));

vi.mock('fs', () => ({
  existsSync: vi.fn(() => false),
  readFileSync: vi.fn(() => '0'),
  unlinkSync: vi.fn(),
}));

import SshCommandAction from './SshCommandAction.js';

function createMockUD() {
  return { showAlert: vi.fn() };
}

describe('SshCommandAction', () => {
  let action;

  beforeEach(() => {
    vi.clearAllMocks();
    action = new SshCommandAction('test-context', createMockUD());
  });

  describe('buildCommand', () => {
    it('builds ssh command with host and command', () => {
      action.updateSettings({ host: 'user@server.com', command: 'uptime' });
      expect(action.buildCommand()).toBe("ssh user@server.com 'uptime'");
    });

    it('escapes single quotes in the remote command', () => {
      action.updateSettings({ host: 'root@10.0.0.1', command: "echo 'hello world'" });
      expect(action.buildCommand()).toBe("ssh root@10.0.0.1 'echo '\\''hello world'\\'''");
    });

    it('returns empty when host is missing', () => {
      action.updateSettings({ command: 'ls' });
      expect(action.buildCommand()).toBe('');
    });

    it('returns empty when command is missing', () => {
      action.updateSettings({ host: 'user@host' });
      expect(action.buildCommand()).toBe('');
    });

    it('returns empty when both are missing', () => {
      expect(action.buildCommand()).toBe('');
    });

    it('rejects host with shell metacharacters', () => {
      action.updateSettings({ host: 'user@host; rm -rf /', command: 'ls' });
      expect(action.buildCommand()).toBe('');
    });

    it('rejects host with backticks', () => {
      action.updateSettings({ host: '`whoami`@host', command: 'ls' });
      expect(action.buildCommand()).toBe('');
    });

    it('rejects host with spaces', () => {
      action.updateSettings({ host: 'user @host', command: 'ls' });
      expect(action.buildCommand()).toBe('');
    });

    it('accepts host with port notation', () => {
      action.updateSettings({ host: 'user@host:22', command: 'ls' });
      expect(action.buildCommand()).toBe("ssh user@host:22 'ls'");
    });

    it('accepts host with dots and dashes', () => {
      action.updateSettings({ host: 'deploy@my-server.example.com', command: 'ls' });
      expect(action.buildCommand()).toBe("ssh deploy@my-server.example.com 'ls'");
    });
  });
});
