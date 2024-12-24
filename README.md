# restore.yazi

[Yazi >=0.4](https://github.com/sxyazi/yazi) plugin to restore/recover latest deleted files/folders.

Note: Because the "ya.confirm() API" is not fully developed yet, if the file to be restored already exists, \
there will be no overwrite confirmation window.

## Requirements

- [yazi](https://github.com/sxyazi/yazi)
- [trash-cli](https://github.com/andreafrancia/trash-cli)
  - If you have `Can't Get Trash Directory` error and running `trash-cli --volumes`
    in terminal
    throw `AttributeError: 'PrintVolumesList' object has no attribute 'run_action'`
    . Remove old version of trash-cli and install newer version of `trash-cli`
    by running command
    `pipx install trash-cli`

## Installation

### Linux/MacOS

```sh
git clone https://github.com/boydaihungst/restore.yazi ~/.config/yazi/plugins/restore.yazi
```

or

```sh
ya pack -a boydaihungst/restore.yazi
```

## Usage

Add this to your `keymap.toml`:

```toml
[manager]
  keymap = [
    { on = "u", run = "plugin restore", desc = "Restore last deleted files/folders" },
    # or du like me
    { on = ["d", "u"], run = "plugin restore", desc = "Restore last deleted files/folders" },
    # ... Other keymaps
  ]
```
