{ pkgs }:

# Wrap an application's bin/ executables without changing the original package.
# Requires targets.genericLinux.gpu to provide /run/opengl-driver, with an
# NVIDIA userspace driver matching the host kernel driver. Supports 64-bit
# NVIDIA Vulkan and GLVND-based OpenGL/EGL, not 32-bit apps or sandboxed apps
# that cannot access the Nix store and /run/opengl-driver.
package:
pkgs.symlinkJoin {
  name = "${package.name}-nix-graphics";
  paths = [ package ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  inherit (package) meta;

  postBuild = ''
    for executable in "$out"/bin/*; do
      if [ -f "$executable" ] && [ -x "$executable" ]; then
        wrapProgram "$executable" \
          --unset VK_ICD_FILENAMES \
          --set VK_DRIVER_FILES /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json \
          --set __GLX_VENDOR_LIBRARY_NAME nvidia \
          --set __EGL_VENDOR_LIBRARY_FILENAMES /run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json \
          --unset __EGL_EXTERNAL_PLATFORM_CONFIG_FILENAMES \
          --set __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS /run/opengl-driver/share/egl/egl_external_platform.d \
          --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib
      fi
    done

    # Copy desktop entries before editing: symlinkJoin links to immutable store
    # files. Pin both bare commands and absolute bin paths to the wrapped bin/.
    if [ -d "$out/share/applications" ]; then
      # FHS packages can symlink whole directories, not just individual files.
      # Materialize each parent before writing desktop entries beneath it.
      for directory in "$out/share" "$out/share/applications"; do
        if [ -L "$directory" ]; then
          target="$(readlink -f "$directory")"
          rm "$directory"
          mkdir "$directory"
          cp -a "$target/." "$directory/"
        fi
        chmod u+w "$directory"
      done
      for desktop in "$out"/share/applications/*.desktop; do
        [ -f "$desktop" ] || continue
        cp --remove-destination "$(readlink -f "$desktop")" "$desktop.tmp"
        mv "$desktop.tmp" "$desktop"
        chmod u+w "$desktop"
        substituteInPlace "$desktop" \
          --replace-quiet '${package}/bin/' "$out/bin/"
        for executable in "$out"/bin/*; do
          [ -x "$executable" ] || continue
          command="$(basename "$executable")"
          substituteInPlace "$desktop" \
            --replace-quiet "Exec=$command " "Exec=$out/bin/$command "
          # Handle commands with no arguments (including TryExec).
          ${pkgs.gnused}/bin/sed -i \
            "s|^Exec=$command\$|Exec=$out/bin/$command|; s|^TryExec=$command\$|TryExec=$out/bin/$command|" \
            "$desktop"
        done
      done
    fi
  '';
}
