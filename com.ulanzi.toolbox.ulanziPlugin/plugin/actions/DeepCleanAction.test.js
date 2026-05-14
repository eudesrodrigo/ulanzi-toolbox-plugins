import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

vi.mock('child_process', () => ({
  exec: vi.fn(),
}));

vi.mock('../executors/executor.js', () => ({
  executeCommand: vi.fn(() => Promise.resolve()),
}));

vi.mock('fs', () => ({
  existsSync: vi.fn(() => false),
  readFileSync: vi.fn(() => '0'),
  unlinkSync: vi.fn(),
}));

import DeepCleanAction, { parseDfOutput } from './DeepCleanAction.js';
import { exec } from 'child_process';
import { executeCommand } from '../executors/executor.js';
import { existsSync, readFileSync } from 'fs';

const DF_OUTPUT = [
  'Filesystem     1G-blocks Used Available Capacity iused    ifree %iused  Mounted on',
  '/dev/disk3s1s1       228   11         6    65%  458116 68378560    1%   /',
].join('\n');

function createMockUD() {
  return {
    showAlert: vi.fn(),
    setStateIcon: vi.fn(),
  };
}

describe('parseDfOutput', () => {
  it('parses standard macOS df -g output', () => {
    expect(parseDfOutput(DF_OUTPUT)).toEqual({ free: 6, total: 228 });
  });

  it('returns null for empty output', () => {
    expect(parseDfOutput('')).toBeNull();
  });

  it('returns null for header-only output', () => {
    expect(parseDfOutput('Filesystem 1G-blocks Used Available')).toBeNull();
  });

  it('returns null for non-numeric values', () => {
    expect(parseDfOutput('header\n/dev/x  abc  def  ghi  50%')).toBeNull();
  });
});

describe('DeepCleanAction', () => {
  let action;
  let $UD;

  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    $UD = createMockUD();
    action = new DeepCleanAction('test-context', $UD);

    vi.mocked(exec).mockImplementation((cmd, cb) => {
      cb(null, DF_OUTPUT);
    });
  });

  afterEach(() => {
    action.stopPolling();
    vi.useRealTimers();
  });

  describe('getDiskUsage', () => {
    it('calls df -g / and returns parsed result', () => {
      const cb = vi.fn();
      action.getDiskUsage(cb);
      expect(exec).toHaveBeenCalledWith('df -g /', expect.any(Function));
      expect(cb).toHaveBeenCalledWith({ free: 6, total: 228 });
    });

    it('returns null on exec error', () => {
      vi.mocked(exec).mockImplementation((cmd, cb) => {
        cb(new Error('fail'));
      });
      const cb = vi.fn();
      action.getDiskUsage(cb);
      expect(cb).toHaveBeenCalledWith(null);
    });
  });

  describe('onAppear', () => {
    it('updates display immediately', () => {
      action.onAppear();
      expect($UD.setStateIcon).toHaveBeenCalledWith('test-context', 0, '6/228 GB');
    });

    it('starts polling timer', () => {
      action.onAppear();
      $UD.setStateIcon.mockClear();

      vi.advanceTimersByTime(60000);
      expect($UD.setStateIcon).toHaveBeenCalledWith('test-context', 0, '6/228 GB');
    });

    it('does not poll while running', () => {
      action.onAppear();
      action.running = true;
      $UD.setStateIcon.mockClear();

      vi.advanceTimersByTime(60000);
      expect($UD.setStateIcon).not.toHaveBeenCalled();
    });
  });

  describe('onDisappear', () => {
    it('stops polling timer', () => {
      action.onAppear();
      action.onDisappear();
      $UD.setStateIcon.mockClear();

      vi.advanceTimersByTime(120000);
      expect($UD.setStateIcon).not.toHaveBeenCalled();
    });
  });

  describe('onActiveChange', () => {
    it('stops polling when deactivated', () => {
      action.onAppear();
      action.onActiveChange(false);
      $UD.setStateIcon.mockClear();

      vi.advanceTimersByTime(120000);
      expect($UD.setStateIcon).not.toHaveBeenCalled();
    });

    it('resumes polling when activated', () => {
      action.onActiveChange(true);
      expect($UD.setStateIcon).toHaveBeenCalledWith('test-context', 0, '6/228 GB');
    });
  });

  describe('execute', () => {
    it('debounces when already running', async () => {
      action.running = true;
      await action.execute();
      expect(executeCommand).not.toHaveBeenCalled();
    });

    it('sets running state icon', async () => {
      await action.execute();
      expect($UD.setStateIcon).toHaveBeenCalledWith('test-context', 1, '...');
    });

    it('calls executeCommand with script path', async () => {
      await action.execute();
      expect(executeCommand).toHaveBeenCalledWith(
        expect.stringContaining('deep-clean.sh'),
        expect.objectContaining({ label: 'Deep Clean' }),
      );
    });

    it('passes terminal setting', async () => {
      action.updateSettings({ terminal: 'iterm' });
      await action.execute();
      expect(executeCommand).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({ terminalId: 'iterm' }),
      );
    });

    it('passes custom label', async () => {
      action.updateSettings({ label: 'Cleanup' });
      await action.execute();
      expect(executeCommand).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({ label: 'Cleanup' }),
      );
    });

    it('passes projectsDir as cwd', async () => {
      action.updateSettings({ projectsDir: '/my/projects' });
      await action.execute();
      expect(executeCommand).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({ cwd: '/my/projects' }),
      );
    });

    it('shows alert on executeCommand failure', async () => {
      vi.mocked(executeCommand).mockRejectedValueOnce(new Error('fail'));
      await action.execute();
      expect($UD.showAlert).toHaveBeenCalledWith('test-context');
    });

    it('stops polling during execution', async () => {
      action.onAppear();
      $UD.setStateIcon.mockClear();
      await action.execute();

      vi.advanceTimersByTime(120000);
      const pollCalls = $UD.setStateIcon.mock.calls.filter(
        (c) => c[1] === 0 && c[2] === '6/228 GB',
      );
      expect(pollCalls).toHaveLength(0);
    });
  });

  describe('pollExitCode', () => {
    it('detects exit file and calls onScriptDone', () => {
      vi.mocked(existsSync).mockReturnValue(true);
      vi.mocked(readFileSync).mockReturnValue('0');

      action.running = true;
      action.pollExitCode('/tmp/test-exit');

      vi.advanceTimersByTime(200);

      expect(action.running).toBe(false);
    });

    it('handles exit code 1 with alert', () => {
      vi.mocked(existsSync).mockReturnValue(true);
      vi.mocked(readFileSync).mockReturnValue('1');

      action.running = true;
      action.pollExitCode('/tmp/test-exit');
      vi.advanceTimersByTime(200);

      expect($UD.showAlert).toHaveBeenCalledWith('test-context');
    });

    it('handles exit code 2 without alert', () => {
      vi.mocked(existsSync).mockReturnValue(true);
      vi.mocked(readFileSync).mockReturnValue('2');

      action.running = true;
      action.pollExitCode('/tmp/test-exit');
      vi.advanceTimersByTime(200);

      expect($UD.showAlert).not.toHaveBeenCalled();
    });

    it('handles TOCTOU error when reading exit file', () => {
      vi.mocked(existsSync).mockReturnValue(true);
      vi.mocked(readFileSync).mockImplementation(() => {
        throw new Error('ENOENT');
      });

      action.running = true;
      action.pollExitCode('/tmp/test-exit');
      vi.advanceTimersByTime(200);

      expect(action.running).toBe(false);
    });

    it('polls repeatedly until exit file appears', () => {
      vi.mocked(existsSync)
        .mockReturnValueOnce(false)
        .mockReturnValueOnce(false)
        .mockReturnValue(true);
      vi.mocked(readFileSync).mockReturnValue('0');

      action.running = true;
      action.pollExitCode('/tmp/test-exit');

      vi.advanceTimersByTime(200);
      expect(action.running).toBe(true);

      vi.advanceTimersByTime(200);
      expect(action.running).toBe(true);

      vi.advanceTimersByTime(200);
      expect(action.running).toBe(false);
    });

    it('stops polling when deactivated', () => {
      vi.mocked(existsSync).mockReturnValue(false);

      action.running = true;
      action.active = false;
      action.pollExitCode('/tmp/test-exit');
      vi.advanceTimersByTime(200);

      expect(action.running).toBe(false);
      expect($UD.showAlert).not.toHaveBeenCalled();
    });
  });

  describe('onScriptDone', () => {
    it('refreshes disk display', () => {
      action.running = true;
      action.onScriptDone('0');
      expect($UD.setStateIcon).toHaveBeenCalledWith('test-context', 0, '6/228 GB');
    });

    it('restarts polling', () => {
      action.running = true;
      action.onScriptDone('0');
      $UD.setStateIcon.mockClear();

      vi.advanceTimersByTime(60000);
      expect($UD.setStateIcon).toHaveBeenCalled();
    });
  });

  describe('buildCommand', () => {
    it('returns quoted path to deep-clean.sh', () => {
      const cmd = action.buildCommand();
      expect(cmd).toContain('deep-clean.sh');
      expect(cmd.startsWith("'")).toBe(true);
      expect(cmd.endsWith("'")).toBe(true);
    });
  });

  describe('updateSettings', () => {
    it('merges settings', () => {
      action.updateSettings({ terminal: 'iterm' });
      action.updateSettings({ label: 'Test' });
      expect(action.settings).toEqual({ terminal: 'iterm', label: 'Test' });
    });
  });
});
