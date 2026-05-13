import { describe, it, expect, vi, beforeEach } from 'vitest';
import { existsSync } from 'fs';

vi.mock('fs', () => ({
  existsSync: vi.fn(),
}));

// Re-import after mock to get fresh module state per test
async function loadModule() {
  vi.resetModules();
  return import('./detect-terminal.js');
}

describe('detectTerminal', () => {
  beforeEach(() => {
    vi.mocked(existsSync).mockReset();
  });

  it('returns iTerm when iTerm.app exists', async () => {
    vi.mocked(existsSync).mockReturnValue(true);
    const { detectTerminal } = await loadModule();

    const result = detectTerminal();
    expect(result).toEqual({ name: 'iTerm2', path: '/Applications/iTerm.app', id: 'iterm' });
  });

  it('returns Terminal.app when iTerm is not installed', async () => {
    vi.mocked(existsSync).mockReturnValue(false);
    const { detectTerminal } = await loadModule();

    const result = detectTerminal();
    expect(result).toEqual({
      name: 'Terminal.app',
      path: '/Applications/Utilities/Terminal.app',
      id: 'terminal',
    });
  });

  it('caches the result after first call', async () => {
    vi.mocked(existsSync).mockReturnValue(true);
    const { detectTerminal } = await loadModule();

    detectTerminal();
    detectTerminal();
    expect(existsSync).toHaveBeenCalledTimes(1);
  });
});

describe('getTerminalById', () => {
  beforeEach(() => {
    vi.mocked(existsSync).mockReset();
  });

  it('returns the terminal matching the id', async () => {
    vi.mocked(existsSync).mockReturnValue(false);
    const { getTerminalById } = await loadModule();

    expect(getTerminalById('terminal')).toEqual({
      name: 'Terminal.app',
      path: '/Applications/Utilities/Terminal.app',
      id: 'terminal',
    });
  });

  it('falls back to auto-detect for "auto"', async () => {
    vi.mocked(existsSync).mockReturnValue(false);
    const { getTerminalById } = await loadModule();

    const result = getTerminalById('auto');
    expect(result.id).toBe('terminal');
  });

  it('falls back to auto-detect for null/undefined', async () => {
    vi.mocked(existsSync).mockReturnValue(true);
    const { getTerminalById } = await loadModule();

    expect(getTerminalById(null).id).toBe('iterm');
    expect(getTerminalById(undefined).id).toBe('iterm');
  });

  it('falls back to auto-detect for unknown id', async () => {
    vi.mocked(existsSync).mockReturnValue(false);
    const { getTerminalById } = await loadModule();

    expect(getTerminalById('nonexistent').id).toBe('terminal');
  });
});

describe('getAvailableTerminals', () => {
  beforeEach(() => {
    vi.mocked(existsSync).mockReset();
  });

  it('always includes auto-detect and Terminal.app', async () => {
    vi.mocked(existsSync).mockReturnValue(false);
    const { getAvailableTerminals } = await loadModule();

    const result = getAvailableTerminals();
    expect(result).toEqual([
      { id: 'auto', name: 'Auto-detect' },
      { name: 'Terminal.app', path: '/Applications/Utilities/Terminal.app', id: 'terminal' },
    ]);
  });

  it('includes iTerm when installed', async () => {
    vi.mocked(existsSync).mockReturnValue(true);
    const { getAvailableTerminals } = await loadModule();

    const result = getAvailableTerminals();
    expect(result).toHaveLength(3);
    expect(result[1]).toEqual({
      name: 'iTerm2',
      path: '/Applications/iTerm.app',
      id: 'iterm',
    });
  });
});
