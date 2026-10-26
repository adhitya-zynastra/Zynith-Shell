# Zynith documentation

## For users

| Page | What it covers |
|---|---|
| [Using Zynith](user/using.md) | key bindings and the parts of the desktop |
| [Configuring Zynith](user/configuring.md) | Settings, the configuration files, the official configurations |
| [Troubleshooting](user/troubleshooting.md) | recovering a desktop that misbehaves, and reporting bugs |
| [The ISO](development/iso.md) | downloading, verifying, testing and installing the Zynith ISO |

## For developers

| Page | What it covers |
|---|---|
| [Architecture](development/architecture.md) | the parts of Zynith, how a session starts, and where configuration and state live |
| [Building and running](development/building.md) | requirements, building and installing from source, running from the tree, recovery |
| [Testing](development/testing.md) | the checks (the same in CI and locally), the test suites |
| [Packaging](development/packaging.md) | the RPMs, how they are built, Quickshell, installing and updating |
| [The ISO](development/iso.md) | how the image is built and validated |
| [Releases](development/releases.md) | versions, how a release is made, the ISO release checklist |

Reference material:

- [`reference/native-shell.example.toml`](reference/native-shell.example.toml): every option of the native shell's
  configuration, with its default.
- [`reference/plugin-api.json`](reference/plugin-api.json): the native shell's Luau plugin API.
