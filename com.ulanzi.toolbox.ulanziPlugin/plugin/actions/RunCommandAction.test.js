import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../executors/executor.js', () => ({
  executeCommand: vi.fn(() => Promise.resolve()),
}));

vi.mock('fs', () => ({
  existsSync: vi.fn(() => false),
  readFileSync: vi.fn(() => '0'),
  unlinkSync: vi.fn(),
}));

import RunCommandAction from './RunCommandAction.js';
import { executeCommand } from '../executors/executor.js';

function createMockUD() {
  return { showAlert: vi.fn() };
}

describe('RunCommandAction', () => {
  let action;
  let $UD;

  beforeEach(() => {
    vi.clearAllMocks();
    $UD = createMockUD();
    action = new RunCommandAction('test-context', $UD);
  });

  describe('buildCommand', () => {
    it('returns the command from settings', () => {
      action.updateSettings({ command: 'echo hello' });
      expect(action.buildCommand()).toBe('echo hello');
    });

    it('returns empty string when no command set', () => {
      expect(action.buildCommand()).toBe('');
    });
  });

  describe('updateSettings', () => {
    it('merges new settings into existing', () => {
      action.updateSettings({ command: 'ls' });
      action.updateSettings({ cwd: '/tmp' });
      expect(action.settings).toEqual({ command: 'ls', cwd: '/tmp' });
    });

    it('overwrites existing keys', () => {
      action.updateSettings({ command: 'ls' });
      action.updateSettings({ command: 'pwd' });
      expect(action.settings.command).toBe('pwd');
    });
  });

  describe('execute', () => {
    it('calls executeCommand with correct options', async () => {
      action.updateSettings({ command: 'make build', label: 'Build', cwd: '/project' });
      await action.execute();

      expect(executeCommand).toHaveBeenCalledWith('make build', {
        label: 'Build',
        cwd: '/project',
        terminalId: undefined,
        exitFile: expect.stringContaining('ulanzi-exit-'),
      });
    });

    it('shows alert when command is empty', async () => {
      await action.execute();
      expect($UD.showAlert).toHaveBeenCalledWith('test-context');
      expect(executeCommand).not.toHaveBeenCalled();
    });

    it('shows alert when executeCommand rejects', async () => {
      action.updateSettings({ command: 'fail' });
      vi.mocked(executeCommand).mockRejectedValueOnce(new Error('osascript failed'));

      await action.execute();
      expect($UD.showAlert).toHaveBeenCalledWith('test-context');
    });

    it('passes terminal setting as terminalId', async () => {
      action.updateSettings({ command: 'ls', terminal: 'iterm' });
      await action.execute();

      expect(executeCommand).toHaveBeenCalledWith(
        'ls',
        expect.objectContaining({ terminalId: 'iterm' }),
      );
    });
  });
});
