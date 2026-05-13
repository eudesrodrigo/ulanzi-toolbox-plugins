---
name: create-ulanzi-plugin
description: Use when the user wants to create, scaffold, or build a new Ulanzi D200 stream deck plugin, add actions to an existing plugin, or asks about Ulanzi plugin development, SDK usage, manifest.json structure, property inspectors, or plugin architecture.
---

# Create Ulanzi D200 Plugin

You are scaffolding a new Ulanzi D200 plugin from scratch.

## Source of Truth

BEFORE creating anything, fetch the latest SDK documentation from these official GitHub repos. These are your PRIMARY reference — this skill provides conventions and gotchas, the repos provide the current API.

| Repo | What to check |
|------|--------------|
| [UlanziDeckPlugin-SDK](https://github.com/UlanziTechnology/UlanziDeckPlugin-SDK) | README: full protocol, manifest schema, lifecycle, debugging, simulator |
| [plugin-common-html](https://github.com/UlanziTechnology/plugin-common-html) | README: HTML SDK API ($UD events, methods, Utils) |
| [plugin-common-node](https://github.com/UlanziTechnology/plugin-common-node) | README: Node.js SDK API (events, methods, Utils) |

If anything in this skill conflicts with the official repos, **the repos win**.

## Reference Implementation

`com.ulanzi.toolbox.ulanziPlugin/` in this repo is a working, tested plugin. Read its files before creating new ones — it is the living template.

## Gather Requirements

Ask the user:
1. **Plugin name** — human-readable (e.g., "OBS Studio")
2. **Plugin ID** — lowercase, no hyphens (e.g., "obsstudio"). Becomes part of the UUID.
3. **Actions** — what buttons? For each: name, behavior on press, PI settings fields.
4. **Main service type** — Node.js (system access) or HTML (canvas, visual)?
5. **Target devices** — D200 only? D200X encoder?

## Directory Structure

```
com.ulanzi.{pluginId}.ulanziPlugin/
  manifest.json
  en.json
  package.json                    # Node.js only
  libs/                           # Copy from toolbox or SDK repos
    css/uspi.css
    js/html-constants.js
    js/eventEmitter.js
    js/html-utils.js
    js/html-ulanziApi.js
    js/constants.js
    js/utils.js
    js/ulanziApi.js               # Node.js only
    js/index.js                   # Node.js only
    js/randomPort.js              # Node.js only
  plugin/
    app.js
    actions/{ActionName}Action.js
    executors/                    # If needed
    utils/
  property-inspector/
    shared/shared-styles.css
    {action-name}/inspector.html
    {action-name}/inspector.js
  assets/store-icon.png
  plugin/icons/{action-name}/idle.png
```

## Naming Conventions (CRITICAL)

```
Plugin folder:     com.ulanzi.{pluginId}.ulanziPlugin
Plugin UUID:       com.ulanzi.ulanzistudio.{pluginId}           (exactly 4 dot-segments)
Action UUID:       com.ulanzi.ulanzistudio.{pluginId}.{action}  (5+ segments, lowercase, no hyphens)
```

## manifest.json

```json
{
  "Author": "...",
  "Name": "...",
  "Description": "...",
  "Icon": "assets/store-icon.png",
  "Version": "1.0.0",
  "Category": "...",
  "CategoryIcon": "assets/store-icon.png",
  "CodePath": "plugin/app.js",
  "Type": "JavaScript",
  "UUID": "com.ulanzi.ulanzistudio.{pluginId}",
  "Actions": [
    {
      "Name": "Action Name",
      "Icon": "plugin/icons/{action-name}/idle.png",
      "PropertyInspectorPath": "property-inspector/{action-name}/inspector.html",
      "States": [{ "Name": "Idle", "Image": "plugin/icons/{action-name}/idle.png" }],
      "Tooltip": "What this action does",
      "UUID": "com.ulanzi.ulanzistudio.{pluginId}.{actionname}",
      "SupportedInMultiActions": true,
      "DisableAutomaticStates": true,
      "Controllers": ["Keypad"]
    }
  ],
  "OS": [{ "Platform": "mac", "MinimumVersion": "12.0" }],
  "Software": { "MinVersion": "3.0.0" }
}
```

Check the SDK README for optional fields: Devices, Encoder, Profiles, ApplicationsToMonitor, InstallToDepsApp, Inspect, PrivateAPI.

## app.js (Main Service)

Follow the ACTION_CACHES pattern:

```javascript
import UlanziApi from '../libs/js/ulanziApi.js';

const PLUGIN_UUID = 'com.ulanzi.ulanzistudio.{pluginId}';
const ACTION_MAP = {
  [`${PLUGIN_UUID}.{actionname}`]: ActionClass,
};
const ACTION_CACHES = {};
const $UD = new UlanziApi();
$UD.connect(PLUGIN_UUID);

$UD.onConnected(() => { /* init global state */ });

$UD.onAdd(jsn => {
  if (!ACTION_CACHES[jsn.context]) createAction(jsn);
  applySettings(jsn);
});

$UD.onRun(jsn => {
  let instance = ACTION_CACHES[jsn.context];
  if (!instance) { instance = createAction(jsn); applySettings(jsn); }
  instance.execute();
});

$UD.onSetActive(jsn => {
  const instance = ACTION_CACHES[jsn.context];
  if (instance) instance.active = jsn.active;
});

$UD.onClear(jsn => {
  if (jsn.param) {
    for (const item of jsn.param) delete ACTION_CACHES[item.context];
  }
});

$UD.onParamFromApp(jsn => applySettings(jsn));
$UD.onParamFromPlugin(jsn => applySettings(jsn));
$UD.onSendToPlugin(jsn => {
  if (jsn.payload?.action === 'test') {
    const instance = ACTION_CACHES[jsn.context];
    if (instance) instance.execute();
  }
});

function createAction(jsn) {
  const ActionClass = ACTION_MAP[jsn.uuid] || DefaultAction;
  ACTION_CACHES[jsn.context] = new ActionClass(jsn.context, $UD);
  return ACTION_CACHES[jsn.context];
}

function applySettings(jsn) {
  const settings = jsn.param || {};
  const instance = ACTION_CACHES[jsn.context];
  if (!instance || Object.keys(settings).length === 0) return;
  instance.updateSettings(settings);
}
```

## Action Class

```javascript
export default class MyAction {
  constructor(context, $UD) {
    this.context = context;
    this.$UD = $UD;
    this.settings = {};
    this.active = true;
  }
  updateSettings(settings) { Object.assign(this.settings, settings); }
  async execute() {
    // Use this.$UD.showAlert(this.context) on error
  }
}
```

## Property Inspector HTML

Script loading order is CRITICAL:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>{Action Name}</title>
  <link rel="stylesheet" href="../../libs/css/uspi.css">
  <link rel="stylesheet" href="../shared/shared-styles.css">
</head>
<body>
  <div class="uspi-wrapper" id="wrapper">

    <div class="tc-section-title">Configuration</div>

    <!-- Text input -->
    <div class="uspi-item">
      <div class="uspi-item-label">Label</div>
      <input class="uspi-item-value" type="text" id="fieldname" placeholder="...">
    </div>

    <!-- Textarea -->
    <div class="uspi-item">
      <div class="uspi-item-label">Command</div>
      <textarea class="uspi-item-value" id="command" placeholder="..."></textarea>
    </div>

    <!-- Browse (file/folder picker) -->
    <div class="uspi-item">
      <div class="uspi-item-label">Directory</div>
      <div class="uspi-item-value tc-browse-group">
        <input type="text" id="path" placeholder="/path/to/dir">
        <button class="tc-browse-btn" id="browse-path" title="Browse...">📁</button>
      </div>
    </div>

    <div class="tc-test-section">
      <button class="tc-test-btn" id="test-btn">▶ Test</button>
    </div>

  </div>

  <script src="../../libs/js/html-constants.js"></script>
  <script src="../../libs/js/eventEmitter.js"></script>
  <script src="../../libs/js/html-utils.js"></script>
  <script src="../../libs/js/html-ulanziApi.js"></script>
  <script src="inspector.js"></script>
</body>
</html>
```

## Property Inspector JS

```javascript
const PI_UUID = 'com.ulanzi.ulanzistudio.{pluginId}.{actionname}';
$UD.connect(PI_UUID);

$UD.onConnected(() => {
  document.getElementById('wrapper').classList.remove('hidden');
});
$UD.onAdd((jsn) => { if (jsn.param) loadSettingsToForm(jsn.param); });
$UD.onParamFromApp((jsn) => { if (jsn.param) loadSettingsToForm(jsn.param); });
$UD.onDidReceiveGlobalSettings((jsn) => {
  if (jsn.settings) { /* update dropdowns from global settings */ }
});

$UD.onSelectdialog((jsn) => {
  if (jsn.path) {
    document.getElementById('target-field').value = jsn.path;
    saveSettings();
  }
});

function loadSettingsToForm(settings) {
  document.getElementById('field1').value = settings.field1 || '';
}

function saveSettings() {
  $UD.sendParamFromPlugin({
    field1: document.getElementById('field1').value,
  });
}

for (const id of ['field1', 'field2']) {
  const el = document.getElementById(id);
  el.addEventListener('change', saveSettings);
  if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
    el.addEventListener('input', saveSettings);
  }
}

document.getElementById('browse-path').addEventListener('click', () => {
  $UD.selectFolderDialog();
});

document.getElementById('test-btn').addEventListener('click', () => {
  $UD.sendToPlugin({ action: 'test' });
  const btn = document.getElementById('test-btn');
  btn.textContent = '⏳ Running...';
  btn.classList.add('testing');
  setTimeout(() => { btn.textContent = '▶ Test'; btn.classList.remove('testing'); }, 3000);
});
```

## en.json

```json
{
  "Localization": {
    "Action Name": "Action Name",
    "Field Label": "Field Label"
  }
}
```

## package.json (Node.js only)

```json
{
  "name": "{plugin-id}",
  "version": "1.0.0",
  "description": "...",
  "main": "plugin/app.js",
  "type": "module",
  "author": "...",
  "license": "MIT",
  "dependencies": { "ws": "^8.18.0" }
}
```

## Icons

- **PNG only** — SVG does NOT work in Ulanzi Studio
- **196x196 pixels**
- Transparent or `#1e1f22` background
- Place in `plugin/icons/{action-name}/idle.png` and `assets/store-icon.png`

## Install and Test

```bash
PLUGIN_DIR="$HOME/Library/Application Support/Ulanzi/UlanziDeck/Plugins"
cp -R com.ulanzi.{pluginId}.ulanziPlugin "$PLUGIN_DIR/"
cd "$PLUGIN_DIR/com.ulanzi.{pluginId}.ulanziPlugin" && npm install
```

Restart Ulanzi Studio. Verify:
1. Plugin appears with correct icon
2. Drag action to button — PI opens with fields
3. Settings persist when navigating away and back
4. Button press executes action
5. Browse buttons populate field

## Gotchas

| # | Gotcha | Consequence |
|---|--------|-------------|
| 1 | Icons MUST be PNG 196x196 | Blank icons |
| 2 | PI MUST use SDK `$UD` — never manual WebSocket | selectdialog + settings break silently |
| 3 | SDK scripts load order: `html-constants` → `eventEmitter` → `html-utils` → `html-ulanziApi` | `$UD` undefined |
| 4 | `onSelectdialog` field is `jsn.path` — NOT `selecteddir`/`selectedfile` | Browse works but field stays empty |
| 5 | Browse inputs need explicit `color`+`background` CSS | White text on white background |
| 6 | Plugin UUID = 4 dot-segments; Action UUID = 5+ | Plugin won't load |
| 7 | `sendParamFromPlugin` saves; `sendToPlugin` is pass-through | Settings lost |
| 8 | `package.json` needs `"type": "module"` | ES module imports fail |
| 9 | `onClear` receives `jsn.param` as ARRAY | Incomplete cleanup |
| 10 | `setSettings` won't save when action inactive | Use `sendParamFromPlugin` |

## SDK Libs

Copy `libs/` from `com.ulanzi.toolbox.ulanziPlugin/libs/` in this repo. To update SDK, fetch from the official repos above.

## Debugging

```bash
open /Applications/Ulanzi\ Studio.app --args --log --webRemoteDebug
```

- PI: `localhost:9292` in Chrome
- Node.js: add `"Inspect": "--inspect=127.0.0.1:9201"` to manifest, use `chrome://inspect`
- Logs: `$UD.logMessage('msg', 'debug')`
