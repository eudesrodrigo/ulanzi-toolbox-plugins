import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../executors/executor.js', () => ({
  executeCommand: vi.fn(() => Promise.resolve()),
}));

vi.mock('fs', () => ({
  existsSync: vi.fn(() => false),
  readFileSync: vi.fn(() => '0'),
  unlinkSync: vi.fn(),
}));

import RunScriptAction from './RunScriptAction.js';
import { executeCommand } from '../executors/executor.js';

function createMockUD() {
  return { showAlert: vi.fn() };
}

describe('RunScriptAction', () => {
  let action;
  let $UD;

  beforeEach(() => {
    vi.clearAllMocks();
    $UD = createMockUD();
    action = new RunScriptAction('test-context', $UD);
  });

  describe('buildCommand', () => {
    it('wraps script path in single quotes', () => {
      action.updateSettings({ script: '/path/to/deploy.sh' });
      expect(action.buildCommand()).toBe("'/path/to/deploy.sh'");
    });

    it('appends args after the quoted script', () => {
      action.updateSettings({ script: '/bin/run.sh', args: '--verbose --dry-run' });
      expect(action.buildCommand()).toBe("'/bin/run.sh' --verbose --dry-run");
    });

    it('escapes single quotes in script path', () => {
      action.updateSettings({ script: "/path/it's/script.sh" });
      expect(action.buildCommand()).toBe("'/path/it'\\''s/script.sh'");
    });

    it('returns empty string when no script set', () => {
      expect(action.buildCommand()).toBe('');
    });

    it('returns empty string for empty script', () => {
      action.updateSettings({ script: '' });
      expect(action.buildCommand()).toBe('');
    });
  });

  describe('execute', () => {
    it('auto-sets cwd to script directory when cwd is not set', async () => {
      action.updateSettings({ script: '/home/user/scripts/deploy.sh' });
      await action.execute();

      expect(executeCommand).toHaveBeenCalledWith(
        "'/home/user/scripts/deploy.sh'",
        expect.objectContaining({ cwd: '/home/user/scripts' }),
      );
    });

    it('preserves explicit cwd over auto-detected', async () => {
      action.updateSettings({ script: '/scripts/deploy.sh', cwd: '/override' });
      await action.execute();

      expect(executeCommand).toHaveBeenCalledWith(
        "'/scripts/deploy.sh'",
        expect.objectContaining({ cwd: '/override' }),
      );
    });

    it('shows alert when no script set', async () => {
      await action.execute();
      expect($UD.showAlert).toHaveBeenCalledWith('test-context');
    });
  });
});
