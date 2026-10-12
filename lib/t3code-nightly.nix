{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  runtimeShell,
  releasesFile,
}:
let
  pname = "t3code-desktop";
  arch = {
    x86_64-linux = "x86_64";
    aarch64-linux = "arm64";
  }.${stdenv.hostPlatform.system};
  isAppImage = asset: lib.hasSuffix "-${arch}.AppImage" asset.name;
  releases = builtins.fromJSON (builtins.readFile releasesFile);
  candidates = builtins.filter (
    release:
    !release.draft
    && lib.hasPrefix "v" release.tag_name
    && lib.hasInfix "-nightly." release.tag_name
    && builtins.any isAppImage release.assets
  ) releases;
  sorted = builtins.sort (a: b: a.published_at > b.published_at) candidates;
  release =
    if sorted == [ ] then
      throw "No T3 Code desktop nightly AppImage found in locked release metadata"
    else
      builtins.head sorted;
  version = lib.removePrefix "v" release.tag_name;
  asset = lib.findFirst isAppImage null release.assets;
  src = fetchurl {
    url = asset.browser_download_url;
    sha256 =
      if asset.digest != null && lib.hasPrefix "sha256:" asset.digest then
        lib.removePrefix "sha256:" asset.digest
      else
        throw "T3 Code nightly AppImage has no SHA-256 digest";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    # Match upstream DesktopCliShim: run the bundled server CLI, not the GUI.
    # Reuse the AppImage's FHS environment for Electron and native modules.
    cat > "$out/bin/t3" <<EOF
    #!${runtimeShell}
    export ELECTRON_RUN_AS_NODE=1
    export T3CODE_CLI_PATH="$out/bin/t3"
    export T3CODE_HOME="\''${T3CODE_HOME:-\$HOME/.t3}"
    exec "$out/bin/${pname}" "${contents}/resources/app.asar/apps/server/dist/bin.mjs" "\$@"
    EOF
    chmod +x "$out/bin/t3"
    mkdir -p "$out/share/applications"
    for desktop in ${contents}/*.desktop; do
      install -m444 "$desktop" "$out/share/applications/$(basename "$desktop")"
    done
    for desktop in "$out"/share/applications/*.desktop; do
      sed -i -E \
        -e 's|^Exec=[^ ]+|Exec=${pname}|' \
        -e 's|^TryExec=.*|TryExec=${pname}|' "$desktop"
    done
    if [ -d ${contents}/usr/share/icons ]; then
      cp -r ${contents}/usr/share/icons "$out/share/"
    fi
  '';

  meta = {
    description = "T3 Code desktop nightly";
    homepage = "https://github.com/pingdotgg/t3code";
    mainProgram = pname;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
