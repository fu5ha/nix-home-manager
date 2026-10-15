# nix home manager config

My home manager config.

Used within [winter](https://github.com/fu5ha/winter), a uBlue (Bazzite)-based atomic distro with Nix installed on top.

Version control is [jj](https://jj-vcs.github.io/) (this repo is colocated with git).

## Updating

Most things (nixpkgs, pi, codex, …):

```sh
nix flake update
home-manager switch --flake .#gray
```

T3 Code is the exception; see below.

## T3 Code

Temporarily built from source against a pinned upstream nightly (`lib/t3code/`, forked from numtide/llm-agents.nix), because Pi needs post-0.0.45 orchestration v2 work that has no stable release yet. `nix flake update` does **not** move it — the version is pinned in `lib/t3code/unwrapped.nix`.

To update:

```sh
scripts/update-t3code.py          # newest nightly, or pass a version, e.g. 0.0.46-nightly.20261015.3171
jj diff                           # review the bump
home-manager switch --flake .#gray
```

The script updates the version, source, and pnpm/SPDX/cargo hashes, and builds `.#t3code-src` to verify. It stops before the switch. The switch restarts the `t3code` user service (`t3 serve --tailscale-serve`, defined in `home.nix`) on the new binary.
