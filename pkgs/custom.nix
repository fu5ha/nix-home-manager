{
  pkgs,
  username,
  ...
}: {
  fedoraHost = pkgs.stdenv.mkDerivation {
    name = "fedoraHost";
    src = null;

    buildInputs = [];

    phases = ["installPhase"];

    installPhase = ''
            mkdir -p $out/bin

            cat <<EOF > $out/bin/buildah
      #!/bin/bash
      /usr/bin/flatpak-spawn --host buildah "\$@"
      EOF

            cat <<EOF > $out/bin/bootc
      #!/bin/bash
      /usr/bin/flatpak-spawn --host pkexec bootc "\$@"
      EOF

            cat <<EOF > $out/bin/firefox
      #!/bin/bash
      /usr/bin/flatpak-spawn --env=DISPLAY=:0 --host firefox "\$@"
      EOF

            cat <<EOF > $out/bin/flatpak
      #!/bin/bash
      /usr/bin/flatpak-spawn --host flatpak "\$@"
      EOF

            cat <<EOF > $out/bin/podman
      #!/bin/bash
      /usr/bin/flatpak-spawn --host podman "\$@"
      EOF

            cat <<EOF > $out/bin/rpm-ostree
      #!/bin/bash
      /usr/bin/flatpak-spawn --host rpm-ostree "\$@"
      EOF

            cat <<EOF > $out/bin/xdg-open
      #!/bin/bash
      /usr/bin/flatpak-spawn --env=DISPLAY=:0 --host xdg-open "\$@"
      EOF

            cat <<EOF > $out/bin/ujust
      #!/bin/bash
      /usr/bin/flatpak-spawn --host ujust "\$@"
      EOF

            cat <<EOF > $out/bin/bluebuild
      #!/bin/bash
      /run/host/bin/bluebuild "\$@"
      EOF

            chmod +x $out/bin/*
    '';
  };
}
