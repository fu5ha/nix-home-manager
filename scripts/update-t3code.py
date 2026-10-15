#!/usr/bin/env python3
"""Bump the pinned t3code nightly in lib/t3code/unwrapped.nix and build it.

Usage:
    scripts/update-t3code.py [version]

With no argument, picks the newest `v*-nightly.*` release from GitHub.
Updates `version`, the source hash, and (via build hash-mismatch errors)
the pnpmDeps / SPDX / cargoHash hashes, then builds `.#t3code-src` to
verify. It stops there: review `jj diff`, then run
`home-manager switch --flake .#gray` yourself.

If a build fails for a non-hash reason (e.g. the DesktopEnvironment
postPatch no longer applies), the file is left edited so you can fix it
by hand; `jj restore lib/t3code/unwrapped.nix` undoes the bump.
"""

import json
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILE = ROOT / "lib/t3code/unwrapped.nix"
REPO = "pingdotgg/t3code"

# Distinct placeholder hashes so a build error's "specified:" line tells
# us exactly which field to fill in with the "got:" hash.
FAKE_PNPM = "sha256-" + "A" * 43 + "="
FAKE_SPDX = "sha256-" + "B" * 43 + "="

POSTPATCH_LINE = "backendCwd: input.isPackaged ? homeDirectory : appRoot,"


def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, text=True, **kwargs)


def latest_nightly():
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/releases?per_page=100",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "update-t3code"},
    )
    with urllib.request.urlopen(req) as resp:
        releases = json.load(resp)
    # The API returns releases newest first.
    for release in releases:
        tag = release["tag_name"]
        if re.fullmatch(r"v[0-9.]+-nightly\..+", tag):
            return tag[1:]
    sys.exit("error: no nightly release found on GitHub")


def sub_once(text, pattern, replacement, what):
    new, n = re.subn(pattern, replacement, text, count=1)
    if n != 1:
        sys.exit(f"error: could not find {what} in {FILE.relative_to(ROOT)}; update the script")
    return new


def build_until_hashes_settle():
    for _ in range(8):
        proc = subprocess.Popen(
            ["nix", "build", ".#t3code-src", "--no-link", "--print-out-paths"],
            cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        output = []
        for line in proc.stdout:
            print(line, end="")
            output.append(line)
        if proc.wait() == 0:
            return

        pairs = re.findall(r"specified:\s*(sha256-[\w+/=]+).*?\n\s*got:\s*(sha256-[\w+/=]+)",
                           "".join(output), re.S)
        if not pairs:
            sys.exit("error: build failed for a non-hash reason (see output above); "
                     "leaving the bump in place for manual fixing")
        specified, got = pairs[-1]
        text = FILE.read_text()
        if specified not in text:
            sys.exit(f"error: build wants hash {specified}, which is not in the file; "
                     "leaving the bump in place for manual fixing")
        print(f"--> hash: {specified} -> {got}")
        FILE.write_text(text.replace(specified, got, 1))
    sys.exit("error: hashes did not settle after 8 builds")


def main():
    if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1] in ("-h", "--help")):
        sys.exit(__doc__)

    text = FILE.read_text()
    current = re.search(r'^  version = "([^"]+)";', text, re.M).group(1)
    target = sys.argv[1].removeprefix("v") if len(sys.argv) == 2 else latest_nightly()
    print(f"t3code: {current} -> {target}")
    if target == current:
        print("already at the requested version; nothing to do")
        return

    # Prefetch the new source first: gives the src hash and a local copy
    # of the tree for pre-flight checks against upstream changes.
    url = f"https://github.com/{REPO}/archive/refs/tags/v{target}.tar.gz"
    prefetch = json.loads(run("nix", "store", "prefetch-file", "--unpack",
                              "--name", "source", "--json", url,
                              capture_output=True).stdout)
    src = Path(prefetch["storePath"])

    desktop_env = (src / "apps/desktop/src/app/DesktopEnvironment.ts").read_text()
    if POSTPATCH_LINE not in desktop_env:
        sys.exit("error: the DesktopEnvironment postPatch line changed upstream; "
                 "update postPatch in lib/t3code/unwrapped.nix before bumping")

    licenses_ts = (src / "scripts/lib/third-party-licenses.ts").read_text()
    m = re.search(r'^const SPDX_LICENSE_LIST_REVISION = "([^"]+)";', licenses_ts, re.M)
    if not m:
        sys.exit("error: SPDX_LICENSE_LIST_REVISION not found upstream; check the postPatch")
    spdx_rev = m.group(1)

    electron = json.loads((src / "apps/desktop/package.json").read_text())["dependencies"]["electron"]
    upstream_major = int(re.sub(r"\D", " ", electron).split()[0])
    nix_major = int(re.search(r"electron_(\d+)", text).group(1))
    if upstream_major > nix_major:
        sys.exit(f"error: upstream wants Electron {electron}, but the packaging "
                 f"pins electron_{nix_major} (nixpkgs must catch up first)")

    text = sub_once(text, r'(?m)^  version = "[^"]+";',
                    f'  version = "{target}";', "version")
    text = sub_once(text, r'(repo = "t3code";\s+tag = "v\$\{version\}";\s+hash = )"[^"]+"',
                    rf'\1"{prefetch["hash"]}"', "src hash")
    text = sub_once(text, r'(fetcherVersion = 4;\s+hash = )"[^"]+"',
                    rf'\1"{FAKE_PNPM}"', "pnpmDeps hash")
    pinned_spdx = re.search(r'repo = "license-list-data";\s+rev = "([^"]+)"', text).group(1)
    if spdx_rev != pinned_spdx:
        print(f"SPDX license list: {pinned_spdx} -> {spdx_rev}")
        text = sub_once(text, r'(repo = "license-list-data";\s+rev = )"[^"]+"',
                        rf'\1"{spdx_rev}"', "spdxLicenses rev")
        text = sub_once(text, r'(sparseCheckout = \[ "json/details" \];\s+hash = )"[^"]+"',
                        rf'\1"{FAKE_SPDX}"', "spdxLicenses hash")
    FILE.write_text(text)

    build_until_hashes_settle()

    print(f"\nt3code {target} builds. Next:")
    print("  jj diff                              # review the bump")
    print("  home-manager switch --flake .#gray   # activate (restarts the t3code service)")


if __name__ == "__main__":
    main()
