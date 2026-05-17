# config.nu
#
# Installed by:
# version = "0.112.2"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# Nushell sets "sensible defaults" for most configuration settings, 
# so your `config.nu` only needs to override these defaults if desired.
#
# You can open this file in your default editor using:
#     config nu
#
# You can also pretty-print and page through the documentation for configuration
# options using:
#     config nu --doc | nu-highlight | less -R
use std/util "path add"

path add "~/.local/bin"
path add "~/bin"
path add "/home/linuxbrew/.linuxbrew/bin"

path add "~/.cargo/bin"
path add "~/.radicle/bin"

# add host exec override folder to path if in a distrobox
if ('CONTAINER_ID' in $env) {
  path add "~/.local/distrobox-host-bin/"
}

$env.config.buffer_editor = "hx"
$env.hm-path = "~/.config/home-manager"

$env.EDITOR = "hx"
