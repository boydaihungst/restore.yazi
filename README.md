# restore.yazi

<!--toc:start-->

- [restore.yazi](#restoreyazi)
  - [Requirements](#requirements)
  - [Installation](#installation)
    - [Linux/MacOS](#linuxmacos)
  - [Usage](#usage)
  <!--toc:end-->

[Yazi >=0.4](https://github.com/sxyazi/yazi) plugin to restore/recover latest deleted files/folders.

Note: Because the "ya.confirm() API" is not fully developed yet, if the file to be restored already exists, \
there will be no overwrite confirmation window.

## Requirements

- [yazi](https://github.com/sxyazi/yazi)
- [trash-cli](https://github.com/andreafrancia/trash-cli)
  - If you have `Can't Get Trash Directory` error and running `trash-cli --volumes`
    in terminal throw `AttributeError: 'PrintVolumesList' object has no attribute 'run_action'`.
    Remove the old version of trash-cli and install newer version [How to install](https://github.com/andreafrancia/trash-cli?tab=readme-ov-file#the-easy-way).

## Installation

### Linux/MacOS

```sh
git clone https://github.com/boydaihungst/restore.yazi ~/.config/yazi/plugins/restore.yazi
```

or

```sh
ya pack -a boydaihungst/restore
```

## Usage

1. Key binding

   - Add this to your `keymap.toml`:

     ```toml
     [manager]
       keymap = [
         { on = "u", run = "plugin restore", desc = "Restore last deleted files/folders" },
         # or use "d + u" like me
         { on = ["d", "u"], run = "plugin restore", desc = "Restore last deleted files/folders" },
         # ... Other keymaps
       ]
     ```

2. Configuration (Optional)

   - Default:

     ```lua
     require("restore"):setup({
         -- Set the position for confirm and overwrite dialogs.
         -- don't forget to set height: `h = xx`
         -- https://yazi-rs.github.io/docs/plugins/utils/#ya.input
         position = { "center", w = 70, h = 40 },

         -- Show confirm dialog before restore.
         -- NOTE: even if set this to false, overwrite dialog still pop up
         show_confirm = true,

         -- colors for confirm and overwrite dialogs
         theme = {
           title = "blue",
           header = "green",
           -- header color for overwrite dialog
           header_warning = "yellow",
           list_item = { odd = "blue", even = "blue" },
         },
     })
     ```
