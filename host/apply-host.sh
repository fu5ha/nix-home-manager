#!/bin/sh
# One-time host setup that Home Manager cannot do unprivileged:
#  - enable linger so user services start at boot without a login
#  - install the plasmalogin autologin drop-in (system paths only)
#  - remove Bazzite's leftover plasma-setup autologin, which would
#    otherwise override ours and fail every boot
# Run interactively (it uses sudo) after a fresh install, or whenever
# the home-manager drift check complains. Safe to re-run.
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

sudo install -Dm644 "$here/50-autologin.conf" /etc/plasmalogin.conf.d/50-autologin.conf
sudo rm -f /etc/plasmalogin.conf.d/99-plasma-setup.conf
sudo loginctl enable-linger "$(id -un)"

cat <<'EOF'
Host setup applied. Autologin takes effect on next boot.

Manual one-time steps still needed:
  1. KWalletManager -> set the kdewallet password to empty, so the
     wallet opens without a prompt in the autologin session.
  2. tailscale login
EOF
