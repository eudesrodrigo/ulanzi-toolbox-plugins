# Ulanzi Toolbox Plugins

Execute terminal commands, scripts, and SSH commands with a single button press on your Ulanzi D200.

## Install

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/eudesrodrigo/ulanzi-toolbox-plugins/main/install.sh)"
```

Or clone and install locally:

```sh
git clone https://github.com/eudesrodrigo/ulanzi-toolbox-plugins.git
cd ulanzi-toolbox-plugins
./install.sh
```

## Actions

| Action          | Description                                  |
| --------------- | -------------------------------------------- |
| **Run Command** | Execute any terminal command                 |
| **Run Script**  | Run a script file (.sh, .py, .js, .rb, etc.) |
| **SSH Command** | Execute a command on a remote host via SSH   |

Each action shows real-time status on the key: idle, running, success, or error.

## Requirements

- macOS 12+
- [Ulanzi Studio](https://www.ulanzi.com) 3.0+
- Node.js (bundled with Ulanzi Studio, or system install)

## Uninstall

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/eudesrodrigo/ulanzi-toolbox-plugins/main/uninstall.sh)"
```

## License

MIT
