import UlanziApi from '../libs/js/ulanziApi.js';
import { detectTerminal, getAvailableTerminals } from './utils/detect-terminal.js';
import RunCommandAction from './actions/RunCommandAction.js';
import RunScriptAction from './actions/RunScriptAction.js';
import SshCommandAction from './actions/SshCommandAction.js';
import DeepCleanAction from './actions/DeepCleanAction.js';
import AICleanAction from './actions/AICleanAction.js';

const PLUGIN_UUID = 'com.ulanzi.ulanzistudio.toolbox';

const ACTION_MAP = {
  [`${PLUGIN_UUID}.runcommand`]: RunCommandAction,
  [`${PLUGIN_UUID}.runscript`]: RunScriptAction,
  [`${PLUGIN_UUID}.sshcommand`]: SshCommandAction,
  [`${PLUGIN_UUID}.deepclean`]: DeepCleanAction,
  [`${PLUGIN_UUID}.aiclean`]: AICleanAction,
};

const ACTION_CACHES = {};
const $UD = new UlanziApi();

$UD.connect(PLUGIN_UUID);

$UD.onConnected(() => {
  const terminal = detectTerminal();
  const available = getAvailableTerminals();
  $UD.setGlobalSettings({ detectedTerminal: terminal.id, availableTerminals: available });
});

function createAction(jsn) {
  const ActionClass = ACTION_MAP[jsn.uuid] || RunCommandAction;
  ACTION_CACHES[jsn.context] = new ActionClass(jsn.context, $UD);
  return ACTION_CACHES[jsn.context];
}

function applySettings(jsn) {
  const settings = jsn.param || {};
  const instance = ACTION_CACHES[jsn.context];
  if (!instance || Object.keys(settings).length === 0) return;
  instance.updateSettings(settings);
}

$UD.onAdd((jsn) => {
  if (!ACTION_CACHES[jsn.context]) createAction(jsn);
  applySettings(jsn);
  ACTION_CACHES[jsn.context]?.onAppear?.();
});

$UD.onSetActive((jsn) => {
  const instance = ACTION_CACHES[jsn.context];
  if (instance) {
    instance.active = jsn.active;
    instance.onActiveChange?.(jsn.active);
  }
});

$UD.onRun((jsn) => {
  let instance = ACTION_CACHES[jsn.context];
  if (!instance) {
    instance = createAction(jsn);
    applySettings(jsn);
  }
  instance.execute();
});

$UD.onClear((jsn) => {
  if (jsn.param) {
    for (const item of jsn.param) {
      ACTION_CACHES[item.context]?.onDisappear?.();
      delete ACTION_CACHES[item.context];
    }
  }
});

$UD.onParamFromApp((jsn) => applySettings(jsn));
$UD.onParamFromPlugin((jsn) => applySettings(jsn));

$UD.onSendToPlugin((jsn) => {
  if (jsn.payload?.action === 'test') {
    const instance = ACTION_CACHES[jsn.context];
    if (instance) instance.execute();
  }
});
