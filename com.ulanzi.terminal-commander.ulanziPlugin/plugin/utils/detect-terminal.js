import { existsSync } from 'fs';

const TERMINALS = {
  iterm: { name: 'iTerm2', path: '/Applications/iTerm.app', id: 'iterm' },
  terminal: { name: 'Terminal.app', path: '/Applications/Utilities/Terminal.app', id: 'terminal' },
};

let detected = null;

export function detectTerminal() {
  if (detected) return detected;

  if (existsSync(TERMINALS.iterm.path)) {
    detected = TERMINALS.iterm;
  } else {
    detected = TERMINALS.terminal;
  }

  return detected;
}

export function getTerminalById(id) {
  if (id === 'auto' || !id) return detectTerminal();
  return TERMINALS[id] || detectTerminal();
}

export function getAvailableTerminals() {
  const available = [{ id: 'auto', name: 'Auto-detect' }];
  if (existsSync(TERMINALS.iterm.path)) {
    available.push(TERMINALS.iterm);
  }
  available.push(TERMINALS.terminal);
  return available;
}
