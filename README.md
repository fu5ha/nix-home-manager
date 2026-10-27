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

