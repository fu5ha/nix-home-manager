# Forked verbatim from numtide/llm-agents.nix packages/versionCheckHomeHook/
# (same rev as ../unwrapped.nix); unwrapped.nix expects it in scope.
{
  lib,
  makeSetupHook,
}:

makeSetupHook {
  name = "version-check-home-hook";
  passthru.hideFromDocs = true;
  meta = {
    description = "Setup hook that provides a writable HOME for versionCheckHook";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
} ./version-check-home.sh
