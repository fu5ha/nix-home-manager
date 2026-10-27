{
  lib,
  pkgs,
  extra-pkgs,
  ...
}:
let
  # Use (withNixGraphics pkgs.someApp) for Nix GUI apps needing NVIDIA graphics.
  withNixGraphics = import ./lib/with-nix-graphics.nix { inherit pkgs; };
  # Fork build (~/git/zed, jj-inbox-fork), plain package without nixpkgs'
  # FHS wrapper; its bin/zed CLI execs libexec/zed-editor and inherits
  # these graphics env vars.
  zed = withNixGraphics extra-pkgs.zed;

  nvidiaVersion = "615.78.08";
  nvidiaSha256 = "sha256-Pj9t3cLudnoIGFMAr3vjyyhuznZpjS3eNSRZl4LQf/4=";
  nvidiaDriver =
    (pkgs.linuxPackages.nvidiaPackages.mkDriver {
      version = nvidiaVersion;
      sha256_64bit = nvidiaSha256;
      sha256_aarch64 = nvidiaSha256;
      useSettings = false;
      usePersistenced = false;
    }).override
      {
        libsOnly = true;
      };

  sopsAgeKey = pkgs.writeShellApplication {
    name = "sops-age-key";
    runtimeInputs = [
      pkgs.bitwarden-cli
      pkgs.jq
    ];
    text = ''
      export HOME=/var/lib/vaultbroker
      export BITWARDENCLI_APPDATA_DIR=/var/lib/vaultbroker/bw-sops
      cd /

      if [ "''${1:-}" = login ]; then
        bw config server "$(jq -r .vaultwarden_url /etc/vaultbroker/config.json)"
        exec bw login
      fi

      printf 'Bitwarden master password: ' >/dev/tty
      read -rs BW_PASSWORD </dev/tty
      printf '\n' >/dev/tty
      export BW_PASSWORD
      BW_SESSION=$(bw unlock --raw --passwordenv BW_PASSWORD)
      unset BW_PASSWORD
      export BW_SESSION
      trap 'bw lock >/dev/null' EXIT

      bw sync >/dev/null
      bw get notes 3d64bbcc-c89f-482d-a5ed-e7559d16c06a
    '';
  };

  extraPkgs = [
    # extra-pkgs.colgrep
    extra-pkgs.pi
    extra-pkgs.codex
    extra-pkgs.muse-code
    extra-pkgs.claude-code
    # agent-browser intentionally not installed on the host: it lives in
    # the helpers container; Pi reaches it via MCP over `podman exec`.
    # extra-pkgs.opencode2
    # llm-agents t3code: `t3` CLI from the main output, desktop app
    # from the `desktop` output.
    extra-pkgs.t3code
    (withNixGraphics extra-pkgs.t3code.desktop)

    extra-pkgs.helix

    zed

    sopsAgeKey
  ];

  nixPkgs = with pkgs; [
    # basic shell tools
    nushell
    htop
    jq
    just
    gh
    starship
    zoxide
    eza
    sendme
    dumbpipe

    # jj
    jujutsu
    jjui
    jj-starship

    # node
    fnm

    # rad
    # radicle-node
    # radicle-tui
    # radicle-desktop

    # nix
    nixfmt
    nixd
    fh
    devenv
  ];
in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "gray";
  home.homeDirectory = "/home/gray";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.11"; # Please read the comment before changing.

  nixpkgs.config.allowUnfree = true;

  # GPU config. must update here if drivers update
  # https://nix-community.github.io/home-manager/index.xhtml#sec-usage-gpu-non-nixos
  nixpkgs.config = {
    nvidia.acceptLicense = true;
    cudaCapabilities = [ "7.5" ];
    cudaForwardCompat = true;
    cudaSupport = true;
  };

  targets.genericLinux = {
    enable = true;
    gpu = {
      enable = true;
      # Home Manager's genericLinux.gpu env currently omits NVIDIA EGL external
      # platform packages. NixOS includes these in hardware.graphics for NVIDIA;
      # GTK/WebKitGTK EGL acceleration needs them.
      #
      # See also the sessionVariables related to selecting the correct icds
      drivers = lib.mkForce (
        pkgs.buildEnv {
          name = "non-nixos-gpu";
          paths = [
            pkgs.mesa
            pkgs.libvdpau-va-gl
            pkgs.intel-media-driver
            nvidiaDriver
            pkgs.nvidia-vaapi-driver
            pkgs.egl-wayland
            pkgs.egl-gbm
            pkgs.egl-wayland2
            pkgs.egl-x11
          ];
        }
      );
      nvidia = {
        enable = true;
        sha256 = nvidiaSha256;
        version = nvidiaVersion;
      };
    };
  };

  home.packages = nixPkgs ++ extraPkgs;

  # T3 Code background service, replacing `t3 service install`.
  #
  # Do not use the upstream installer (`t3 service install`): it would
  # download a self-pinned runtime into ~/.t3/runtime/versions and point
  # the unit at its `__service-launcher`, i.e. a second copy of t3 that
  # `t3 update` mutates outside Nix. Upstream's launcher ultimately just
  # spawns `<t3> serve`, so run the Nix-packaged one directly; updates
  # then flow through home-manager switches like everything else. Do not rely on
  # `t3 service status` either (it compares against the upstream-pinned
  # unit); manage this with `systemctl --user {status,restart,stop} t3code`
  # and `journalctl --user -u t3code` instead.
  #
  # Note: starts on login. To also start at boot / survive logout, linger
  # must be enabled once (Home Manager cannot do that); see host/apply-host.sh.
  systemd.user.startServices = "sd-switch";
  systemd.user.services.t3code = {
    Unit = {
      Description = "T3 Code server";
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "%h";
      Environment = [
        "T3CODE_HOME=%h/.t3"
        # Same marker upstream's unit sets so the server knows it runs as
        # the boot service (it also detects this from its cgroup name).
        "T3_BOOT_SERVICE_UNIT=t3code.service"
      ];
      # Headless server; no need for the GPU-wrapped desktop package.
      # --tailscale-serve: the server runs `tailscale serve` to expose its
      # loopback backend at https://bazzite.<tailnet>.ts.net while it runs
      # (mapping removed on shutdown), so paired remote environments keep
      # working when the desktop app is closed. Requires MagicDNS + HTTPS
      # enabled in the tailnet admin console.
      ExecStart = "${lib.getExe' extra-pkgs.t3code "t3"} serve --tailscale-serve";
      KillMode = "mixed";
      OOMPolicy = "continue";
      Restart = "always";
      RestartSec = 5;
      CPUWeight = 1000;
      IOWeight = 1000;
      ManagedOOMPreference = "avoid";
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.vale-tunnel = {
    Unit.Description = "SSH tunnel to vale agent sockets";
    Service = {
      Type = "simple";
      ExecStart = lib.concatStringsSep " " [
        (lib.getExe pkgs.openssh)
        "-N"
        "-i %h/.ssh/id_ed25519"
        "-o BatchMode=yes"
        "-o ExitOnForwardFailure=yes"
        "-o ServerAliveInterval=30"
        "-o StreamLocalBindUnlink=yes"
        "-L %t/browser-agent.sock:/run/browser-control/agent.sock"
        "-L %t/vaultbroker.sock:/run/vaultbroker/broker.sock"
        "deja@vale.local"
      ];
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Plasma misses .desktop/icon changes from a switch: ksycoca watches
  # applications/ dirs via inotify, which resolves ~/.nix-profile to the
  # store dir's inode at watch time, so retargeting the profile symlink to
  # a new generation produces no event; the mtime fallback sees only the
  # store's 1970 timestamps and also concludes nothing changed. Force a
  # refresh after installing packages. Use the host's kbuildsycoca6 (its
  # cache format must match the running Plasma), and guard everything so a
  # switch outside a Plasma session still succeeds.
  home.activation.plasmaDesktopCache = lib.hm.dag.entryAfter [ "installPackages" ] ''
    # KDE's on-disk icon cache, rebuilt on next use. Must go before the
    # iconChanged signal below so KIconLoader repopulates from scratch.
    rm -f "$HOME/.cache/icon-cache.kcache"

    if [ -x /usr/bin/kbuildsycoca6 ]; then
      /usr/bin/kbuildsycoca6 --noincremental > /dev/null 2>&1 || true
      # The sycoca filename is hashed from the environment, and this
      # shell's XDG_DATA_DIRS can differ from plasmashell's, landing the
      # rebuild in a file Plasma never reads. Re-run under the user
      # manager's environment (the one plasmashell was started with) so
      # its cache file is the one that gets rebuilt.
      XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)} \
        /usr/bin/systemd-run --user --pipe --wait --quiet \
        /usr/bin/kbuildsycoca6 --noincremental > /dev/null 2>&1 || true
    fi

    # Tell running apps to reload icons. This is the signal
    # KIconLoader::emitChange sends on icon-theme changes; it makes each
    # app drop its in-memory pixmap cache and re-scan the theme dirs.
    # Groups: Desktop=0 (launcher/menus), Panel=4 (task manager).
    if [ -n "''${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
      for group in 0 4; do
        /usr/bin/dbus-send --session --type=signal /KIconLoader \
          org.kde.KIconLoader.iconChanged int32:$group > /dev/null 2>&1 || true
      done
    fi
  '';

  home.activation.devenvNushellHook = lib.hm.dag.entryAfter [ "installPackages" ] ''
    mkdir -p "$HOME/.cache/devenv"
    ${pkgs.devenv}/bin/devenv hook nu > "$HOME/.cache/devenv/hook.nu"
  '';

  # S0 session policy: never suspend (also refused system-wide by the
  # winter image), turn displays off after 30 minutes and lock as they
  # go dark, and make the chassis power button lock instead of sleep.
  # LockOnStart pairs with the plasmalogin autologin drop-in installed
  # by host/apply-host.sh: the session starts at boot, already locked,
  # with the (passwordless) wallet open for user services. Written with
  # the host's kwriteconfig6 into the real ~/.config files, since KDE
  # both reads and writes these; symlinks into the Nix store would fight it.
  # PowerDevil action enums: 0 = do nothing, 32 = lock screen.
  home.activation.powerAndLock = lib.hm.dag.entryAfter [ "installPackages" ] ''
    if [ -x /usr/bin/kwriteconfig6 ]; then
      kw=/usr/bin/kwriteconfig6
      $kw --file powerdevilrc --group AC --group SuspendAndShutdown --key AutoSuspendAction 0
      $kw --file powerdevilrc --group AC --group SuspendAndShutdown --key PowerButtonAction 32
      $kw --file powerdevilrc --group AC --group Display --key TurnOffDisplayIdleTimeoutSec 1800
      $kw --file powerdevilrc --group AC --group Display --key LockBeforeTurnOffDisplay true
      $kw --file kscreenlockerrc --group Daemon --key LockOnStart true
      $kw --file kscreenlockerrc --group Daemon --key Timeout 30
    fi
  '';

  # Linger and the plasmalogin autologin drop-in live behind sudo, so
  # Home Manager can only verify them. Warn (never fail the switch)
  # when host state drifts from what this repo declares; the fix is
  # host/apply-host.sh.
  home.activation.hostSetupCheck = lib.hm.dag.entryAfter [ "installPackages" ] ''
    apply="run host/apply-host.sh from the home-manager repo"
    if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]; then
      printf 'warning: linger is disabled for %s; %s\n' "$USER" "$apply" >&2
    fi
    if ! cmp -s ${./host/50-autologin.conf} /etc/plasmalogin.conf.d/50-autologin.conf; then
      printf 'warning: /etc/plasmalogin.conf.d/50-autologin.conf differs from host/50-autologin.conf; %s\n' "$apply" >&2
    fi
    if [ -e /etc/plasmalogin.conf.d/99-plasma-setup.conf ]; then
      printf 'warning: leftover /etc/plasmalogin.conf.d/99-plasma-setup.conf overrides autologin; %s\n' "$apply" >&2
    fi
  '';

  programs.nix-index.enable = true;

  programs.git = {
    enable = true;
    settings = {
      user.name = "Gray Olson";
      user.email = "gray@grayolson.com";
      init = {
        defaultBranch = "main";
      };
      credential = {
        "https://github.com".helper = "!gh auth git-credential";
        "https://gist.github.com".helper = "!gh auth git-credential";
      };
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = false;
    settings = {
      git_protocol = "https";
    };
  };

  programs.jujutsu = {
    enable = true;
    settings = {
      user.name = "Gray Olson";
      user.email = "gray@grayolson.com";
      ui.default-command = [ "log" ];
      revsets.log = "@ | ancestors(trunk()..(visible_heads() & mine()), 8) | ancestors(trunk(), 3)";
    };
  };

  programs.jjui = {
    enable = true;
  };

  # programs.radicle = {
  #   enable = true;
  # };

  # services.radicle.node = {
  #   enable = false;
  # };

  programs.nushell = {
    enable = true;
    configFile.source = ./nushell/config.nu;

    shellAliases = {
      hmc = "^($env.config.buffer_editor) ~/.config/home-manager";
    };
    extraConfig = ''
      $env.config.hooks.command_not_found = source ${pkgs.nix-index}/etc/profile.d/command-not-found.nu
    '';
  };

  programs.starship = {
    enable = true;
    enableNushellIntegration = true;
    settings = {
      character = {
        success_symbol = "[~](bold green)";
        error_symbol = "[~](bold red)";
      };
      custom = {
        jj = {
          when = "jj-starship detect";
          shell = "jj-starship";
          format = "$output ";
        };
      };
      git_branch.only_attached = true;
      git_commit.disabled = true;
      git_status.disabled = true;
      container = {
        style = "bold red dimmed";
        format = "[\\[$symbol $name\\]]($style) ";
      };
    };
  };

  programs.eza = {
    enable = true;
    enableNushellIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableNushellIntegration = true;
  };

  programs.helix = {
    enable = true;

    package = extra-pkgs.helix;

    # languages = {
    #   language-server.patchmark = {
    #     command = lib.getExe' extra-pkgs.patchmark "patchmark";
    #   };
    #   language = [
    #     {
    #       name = "markdown";
    #       language-servers = ["patchmark"];
    #     }
    #   ];
    # };
  };

  home.shell = {
    enableShellIntegration = true;
    enableNushellIntegration = true;
  };

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'. There are more specific ways for various
  # programs, and also xdg.configFile & xdg.dataFile. The most specific way
  # should be preferred, use this if there's not a specific way.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  xdg = {
    enable = true;
    # copy to ~/.config
    configFile = {
      "plasma-workspace/env/path.sh".text = "export PATH=$HOME/.local/bin:$PATH";

      "distrobox" = {
        recursive = true;
        source = ./distrobox;
      };

      "ghostty" = {
        recursive = true;
        source = ./ghostty;
      };
    };

    # copy to ~/.local/share
    dataFile = {

    };
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/gray/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    # VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json";
    # __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";
    # __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
