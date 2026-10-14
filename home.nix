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

  nvidiaVersion = "615.71.09";
  nvidiaSha256 = "sha256-zc7tIrvrYSSNGm3qvCWWZz46ZQFpjucayNL9wo87cP4=";
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

  extraPkgs = [
    # extra-pkgs.colgrep
    extra-pkgs.pi
    extra-pkgs.codex
    extra-pkgs.muse-code
    # agent-browser intentionally not installed on the host: it lives in
    # the helpers container; Pi reaches it via MCP over `podman exec`.
    # extra-pkgs.opencode2
    # extra-pkgs.autolith
    # From-source build (lib/t3code): `t3` CLI from the main output,
    # desktop app from the `desktop` output. The AppImage package
    # (extra-pkgs.t3code-desktop) remains as a fallback but is unused.
    extra-pkgs.t3code-src
    (withNixGraphics extra-pkgs.t3code-src.desktop)

    extra-pkgs.helix

    zed
  ];

  nixPkgs = with pkgs; [
    (withNixGraphics vscode-fhs)

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
      drivers = lib.mkForce (pkgs.buildEnv {
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
      });
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
  # then flow through home-manager switches like everything else (plus a
  # manual nightly bump in lib/t3code/unwrapped.nix). Do not rely on
  # `t3 service status` either (it compares against the upstream-pinned
  # unit); manage this with `systemctl --user {status,restart,stop} t3code`
  # and `journalctl --user -u t3code` instead.
  #
  # Note: starts on login. To also start at boot / survive logout, run
  # `sudo loginctl enable-linger gray` once (Home Manager cannot do that).
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
      ExecStart = "${lib.getExe' extra-pkgs.t3code-src "t3"} serve --tailscale-serve";
      KillMode = "mixed";
      OOMPolicy = "continue";
      Restart = "always";
      RestartSec = 5;
      CPUWeight = 1000;
      IOWeight = 1000;
      # Restore "avoid" once Winter ships uresourced >= 0.5.5.
      ManagedOOMPreference = "none";
    };
    Install.WantedBy = [ "default.target" ];
  };

  home.activation.devenvNushellHook = lib.hm.dag.entryAfter [ "installPackages" ] ''
    mkdir -p "$HOME/.cache/devenv"
    ${pkgs.devenv}/bin/devenv hook nu > "$HOME/.cache/devenv/hook.nu"
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
