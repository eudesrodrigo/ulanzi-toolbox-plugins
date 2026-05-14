const PI_UUID = 'com.ulanzi.ulanzistudio.toolbox.deepclean';

$UD.connect(PI_UUID);

$UD.onConnected(() => {
  document.getElementById('wrapper').classList.remove('hidden');
});

$UD.onAdd((jsn) => {
  if (jsn.param) loadSettingsToForm(jsn.param);
});

$UD.onParamFromApp((jsn) => {
  if (jsn.param) loadSettingsToForm(jsn.param);
});

$UD.onDidReceiveGlobalSettings((jsn) => {
  if (jsn.settings) updateTerminalDropdown(jsn.settings.availableTerminals);
});

function loadSettingsToForm(settings) {
  document.getElementById('terminal').value = settings.terminal || 'auto';
}

function updateTerminalDropdown(terminals) {
  if (!terminals) return;
  const select = document.getElementById('terminal');
  const current = select.value;
  while (select.firstChild) select.removeChild(select.firstChild);
  for (const t of terminals) {
    const opt = document.createElement('option');
    opt.value = t.id;
    opt.textContent = t.name;
    select.appendChild(opt);
  }
  select.value = current || 'auto';
}

function saveSettings() {
  $UD.sendParamFromPlugin({
    terminal: document.getElementById('terminal').value,
  });
}

document.getElementById('terminal').addEventListener('change', saveSettings);

document.getElementById('test-btn').addEventListener('click', () => {
  $UD.sendToPlugin({ action: 'test' });
  const btn = document.getElementById('test-btn');
  btn.textContent = 'Running...';
  btn.classList.add('testing');
  setTimeout(() => {
    btn.textContent = 'Test';
    btn.classList.remove('testing');
  }, 3000);
});
