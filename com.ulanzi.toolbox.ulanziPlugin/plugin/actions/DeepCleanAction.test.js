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

import DeepCleanAction, {
  parseDiskutilOutput,
  generateIdleIcon,
  generateRunningIcon,
} from './DeepCleanAction.js';
import { exec } from 'child_process';
import { executeCommand } from '../executors/executor.js';
import { existsSync, readFileSync } from 'fs';

const DISKUTIL_OUTPUT = [
  '   Device Identifier:         disk3s1s1',
  '   Volume Name:               Macintosh HD',
  '   Container Total Space:     245.1 GB (245107195904 Bytes)',
  '   Container Free Space:      5.9 GB (5873102848 Bytes)',
].join('\n');

function createMockUD() {
  return {
    showAlert: vi.fn(),
    setBaseDataIcon: vi.fn(),
  };
}

describe('parseDiskutilOutput', () => {
  it('parses diskutil info / output', () => {
    expect(parseDiskutilOutput(DISKUTIL_OUTPUT)).toEqual({
      free: 6,
      total: 245,
    });
  });

  it('returns null for empty output', () => {
    expect(parseDiskutilOutput('')).toBeNull();
  });

  it('returns null when total is missing', () => {
    expect(parseDiskutilOutput('   Container Free Space:      5.9 GB')).toBeNull();
  });

  it('returns null when free is missing', () => {
    expect(parseDiskutilOutput('   Container Total Space:     245.1 GB')).toBeNull();
  });

  it('returns null for non-numeric values', () => {
    const bad = [
      '   Container Total Space:     abc GB',
      '   Container Free Space:      xyz GB',
    ].join('\n');
    expect(parseDiskutilOutput(bad)).toBeNull();
  });
});

describe('generateIdleIcon', () => {
  it('returns data URI with base64-encoded SVG', () => {
    const icon = generateIdleIcon(6, 245);
    expect(icon).toMatch(/^data:image\/svg\+xml;base64,/);
    const svg = Buffer.from(icon.replace('data:image/svg+xml;base64,', ''), 'base64').toString(
      'utf8',
    );
    expect(svg).toContain('<svg');
    expect(svg).toContain('6/245');
    expect(svg).toContain('GB');
  });

  it('calculates percentage correctly', () => {
    const svg = Buffer.from(
      generateIdleIcon(6, 245).replace('data:image/svg+xml;base64,', ''),
      'base64',
    ).toString('utf8');
    expect(svg).toContain('98% used');
  });

  it('uses red bar color when usage >= 90%', () => {
    const svg = Buffer.from(
      generateIdleIcon(6, 245).replace('data:image/svg+xml;base64,', ''),
      'base64',
    ).toString('utf8');
    expect(svg).toContain('#ff4444');
  });

  it('uses yellow bar color when usage >= 75% and < 90%', () => {
    const svg = Buffer.from(
      generateIdleIcon(50, 200).replace('data:image/svg+xml;base64,', ''),
      'base64',
    ).toString('utf8');
    expect(svg).toContain('#ffaa00');
  });

  it('uses teal bar color when usage < 75%', () => {
    const svg = Buffer.from(
      generateIdleIcon(100, 200).replace('data:image/svg+xml;base64,', ''),
      'base64',
    ).toString('utf8');
    expect(svg).toContain('#00FFE6');
  });

  it('handles zero total', () => {
    const svg = Buffer.from(
      generateIdleIcon(0, 0).replace('data:image/svg+xml;base64,', ''),
      'base64',
    ).toString('utf8');
    expect(svg).toContain('0% used');
  });
});

describe('generateRunningIcon', () => {
  it('returns data URI with base64-encoded SVG', () => {
    const icon = generateRunningIcon();
    expect(icon).toMatch(/^data:image\/svg\+xml;base64,/);
    const svg = Buffer.from(icon.replace('data:image/svg+xml;base64,', ''), 'base64').toString(
      'utf8',
    );
    expect(svg).toContain('<svg');
    expect(svg).toContain('cleaning');
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
      cb(null, DISKUTIL_OUTPUT);
    });
  });

  afterEach(() => {
    action.stopPolling();
    vi.useRealTimers();
  });

  describe('getDiskUsage', () => {
    it('calls diskutil info / and returns parsed result', () => {
      const cb = vi.fn();
      action.getDiskUsage(cb);
      expect(exec).toHaveBeenCalledWith('diskutil info /', expect.any(Function));
      expect(cb).toHaveBeenCalledWith({ free: 6, total: 245 });
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
    it('updates display immediately with base64 icon', () => {
      action.onAppear();
      expect($UD.setBaseDataIcon).toHaveBeenCalledWith(
        'test-context',
        expect.stringMatching(/^data:image\/svg\+xml;base64,/),
      );
      const svg = Buffer.from(
        $UD.setBaseDataIcon.mock.calls[0][1].replace('data:image/svg+xml;base64,', ''),
        'base64',
      ).toString('utf8');
      expect(svg).toContain('6/245');
    });

    it('starts polling timer', () => {
      action.onAppear();
      $UD.setBaseDataIcon.mockClear();

      vi.advanceTimersByTime(60000);
      expect($UD.setBaseDataIcon).toHaveBeenCalled();
    });

    it('does not poll while running', () => {
      action.onAppear();
      action.running = true;
      $UD.setBaseDataIcon.mockClear();

      vi.advanceTimersByTime(60000);
      expect($UD.setBaseDataIcon).not.toHaveBeenCalled();
    });
  });

  describe('onDisappear', () => {
    it('stops polling timer', () => {
      action.onAppear();
      action.onDisappear();
      $UD.setBaseDataIcon.mockClear();

      vi.advanceTimersByTime(120000);
      expect($UD.setBaseDataIcon).not.toHaveBeenCalled();
    });
  });

  describe('onActiveChange', () => {
    it('stops polling when deactivated', () => {
      action.onAppear();
      action.onActiveChange(false);
      $UD.setBaseDataIcon.mockClear();

      vi.advanceTimersByTime(120000);
      expect($UD.setBaseDataIcon).not.toHaveBeenCalled();
    });

    it('resumes polling when activated', () => {
      action.onActiveChange(true);
      expect($UD.setBaseDataIcon).toHaveBeenCalled();
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
      const svg = Buffer.from(
        $UD.setBaseDataIcon.mock.calls[0][1].replace('data:image/svg+xml;base64,', ''),
        'base64',
      ).toString('utf8');
      expect(svg).toContain('cleaning');
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

    it('shows alert on executeCommand failure', async () => {
      vi.mocked(executeCommand).mockRejectedValueOnce(new Error('fail'));
      await action.execute();
      expect($UD.showAlert).toHaveBeenCalledWith('test-context');
    });

    it('stops polling during execution', async () => {
      action.onAppear();
      $UD.setBaseDataIcon.mockClear();
      await action.execute();

      vi.advanceTimersByTime(120000);
      const pollCalls = $UD.setBaseDataIcon.mock.calls.filter((c) => {
        const svg = Buffer.from(c[1].replace('data:image/svg+xml;base64,', ''), 'base64').toString(
          'utf8',
        );
        return svg.includes('6/245');
      });
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
      expect($UD.setBaseDataIcon).toHaveBeenCalled();
      const svg = Buffer.from(
        $UD.setBaseDataIcon.mock.calls[0][1].replace('data:image/svg+xml;base64,', ''),
        'base64',
      ).toString('utf8');
      expect(svg).toContain('6/245');
    });

    it('restarts polling', () => {
      action.running = true;
      action.onScriptDone('0');
      $UD.setBaseDataIcon.mockClear();

      vi.advanceTimersByTime(60000);
      expect($UD.setBaseDataIcon).toHaveBeenCalled();
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
