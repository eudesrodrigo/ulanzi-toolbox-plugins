import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

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
import { existsSync, readFileSync, unlinkSync } from 'fs';

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

  describe('pollExitCode', () => {
    beforeEach(() => {
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it('reads and cleans up exit file when it appears', () => {
      vi.mocked(existsSync).mockReturnValueOnce(true);
      action.pollExitCode('/tmp/exit-file');

      vi.advanceTimersByTime(200);

      expect(readFileSync).toHaveBeenCalledWith('/tmp/exit-file', 'utf-8');
      expect(unlinkSync).toHaveBeenCalledWith('/tmp/exit-file');
    });

    it('stops polling when action is deactivated', () => {
      action.active = false;
      action.pollExitCode('/tmp/exit-file');

      vi.advanceTimersByTime(200);

      expect(existsSync).not.toHaveBeenCalled();
    });

    it('retries when exit file does not exist yet', () => {
      vi.mocked(existsSync).mockReturnValueOnce(false).mockReturnValueOnce(true);
      action.pollExitCode('/tmp/exit-file');

      vi.advanceTimersByTime(200);
      expect(existsSync).toHaveBeenCalledTimes(1);
      expect(readFileSync).not.toHaveBeenCalled();

      vi.advanceTimersByTime(200);
      expect(existsSync).toHaveBeenCalledTimes(2);
      expect(readFileSync).toHaveBeenCalled();
    });

    it('stops polling after timeout', () => {
      vi.mocked(existsSync).mockReturnValue(false);
      action.pollExitCode('/tmp/exit-file');

      vi.advanceTimersByTime(31000);

      const callCount = vi.mocked(existsSync).mock.calls.length;
      vi.advanceTimersByTime(1000);
      expect(vi.mocked(existsSync).mock.calls.length).toBe(callCount);
    });

    it('handles error when exit file disappears between check and read', () => {
      vi.mocked(existsSync).mockReturnValueOnce(true);
      vi.mocked(readFileSync).mockImplementationOnce(() => {
        throw new Error('ENOENT');
      });

      action.pollExitCode('/tmp/exit-file');
      vi.advanceTimersByTime(200);

      expect(existsSync).toHaveBeenCalled();
    });
  });
});
