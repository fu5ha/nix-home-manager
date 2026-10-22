# nix home manager config

My home manager config.

Used within [winter](https://github.com/fu5ha/winter), a uBlue (Bazzite)-based atomic distro with Nix installed on top.

Version control is [jj](https://jj-vcs.github.io/) (this repo is colocated with git).

## Updating

Everything (nixpkgs, pi, codex, t3code, …):

```sh
nix flake update
home-manager switch --flake .#gray
```

## T3 Code

Comes from numtide/llm-agents.nix, overridden in `flake.nix` to bake pi and codex into the wrapper PATH instead of upstream's default providers. llm-agents tracks stable t3code releases, so the normal update flow above moves it. Build it standalone with `nix build .#t3code`. The switch restarts the `t3code` user service (`t3 serve --tailscale-serve`, defined in `home.nix`) on the new binary.

## Temporary notes

### eMudhra CA compromise (2026-10-21)

`flake.nix` carries a temporary overlay that blacklists four roots in `cacert` (Comodo AAA Services root, emSign ECC Root CA - G3, emSign Root CA - C1, emSign ECC Root CA - C3). Compromised eMudhra intermediates chain to them (CVE-2026-111943), and nixos-unstable still ships cacert 3.126.

Check from time to time whether the locked nixpkgs has cacert 3.131.1 or later. To check, run `nix eval .#homeConfigurations.gray.pkgs.cacert.version`. Once it does, remove the overlay and this note, then switch. The overlay only covers clients that use the nixpkgs CA bundle. Update tools with their own roots on their own channels: brew and fnm Node, `uv`, and Electron apps.
