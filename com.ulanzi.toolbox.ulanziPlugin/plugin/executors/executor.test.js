import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('./iterm-executor.js', () => ({
  executeInITerm: vi.fn(() => Promise.resolve()),
}));

vi.mock('./terminal-executor.js', () => ({
  executeInTerminalApp: vi.fn(() => Promise.resolve()),
}));

vi.mock('../utils/detect-terminal.js', () => ({
  getTerminalById: vi.fn(),
}));

import { executeCommand } from './executor.js';
import { executeInITerm } from './iterm-executor.js';
import { executeInTerminalApp } from './terminal-executor.js';
import { getTerminalById } from '../utils/detect-terminal.js';

describe('executeCommand', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('dispatches to iTerm when terminal id is iterm', async () => {
    vi.mocked(getTerminalById).mockReturnValue({ id: 'iterm', name: 'iTerm' });
    const opts = { terminalId: 'iterm', label: 'Test' };

    await executeCommand('ls', opts);

    expect(getTerminalById).toHaveBeenCalledWith('iterm');
    expect(executeInITerm).toHaveBeenCalledWith('ls', opts);
    expect(executeInTerminalApp).not.toHaveBeenCalled();
  });

  it('dispatches to Terminal.app for non-iterm terminals', async () => {
    vi.mocked(getTerminalById).mockReturnValue({ id: 'terminal', name: 'Terminal' });
    const opts = { terminalId: 'terminal' };

    await executeCommand('pwd', opts);

    expect(executeInTerminalApp).toHaveBeenCalledWith('pwd', opts);
    expect(executeInITerm).not.toHaveBeenCalled();
  });

  it('uses default options when none provided', async () => {
    vi.mocked(getTerminalById).mockReturnValue({ id: 'terminal', name: 'Terminal' });

    await executeCommand('echo hi');

    expect(getTerminalById).toHaveBeenCalledWith(undefined);
    expect(executeInTerminalApp).toHaveBeenCalledWith('echo hi', {});
  });
});
