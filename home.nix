{ config, pkgs, username, homeDirectory, ... }: let
  
  customPkgs = import ./pkgs/custom.nix {inherit pkgs username;};
  customPackages = with customPkgs; [
      fedoraHost
  ];

  # The home.packages option allows you to install Nix packages into your
  # environment.
  nixPackages = with pkgs; [
    nushell
    eza
    htop
    jq
    just
    alejandra
    gh
    jujutsu
    jjui
    starship
    jj-starship
  ];

in {
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = username;
  home.homeDirectory = homeDirectory;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.11"; # Please read the comment before changing.

  # GPU config. disabled for now, see the following if needed in future
  # https://nix-community.github.io/home-manager/index.xhtml#sec-usage-gpu-non-nixos
  # targets.genericLinux.gpu = {
  #   enable = true;
  #   nvidia = {
  #     enable = true;
  #     version = "595.71.05"
  #   }
  # };

  nixpkgs = {
    config = {
      allowUnfree = true;
    };
  };

  home.packages = nixPackages ++ customPackages;
  
  programs.git = {
    enable = true;
    settings = {
      user.name = "Gray Olson";
      user.email = "gray@grayolson.com";
    };
  };

  programs.jujutsu = {
    enable = true;
    settings = {
      user.name = "Gray Olson";
      user.email = "gray@grayolson.com";
      ui.default-command = ["log"];
    };
  };

  programs.jjui = {
    enable = true;
  };

  programs.gh = {
    enable = true;
  };

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
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
    ".config/containers/custom/main/main.Containerfile".text = ''
      FROM ghcr.io/thrix/nix-toolbox:44

      RUN dnf install -y @development-tools clang llvm

      RUN dnf install -y nushell git hx zoxide fd rg
    '';

    "distrobox.ini".text = ''
      [main]
      image=main
      nvidia=true
      pull=false
      root=false
      replace=true
      start_now=true
    '';

  };
  hostConfig = {
    enable = true;

    xdgDesktopEntries = true;

    files = [
      ".config/containers/custom/main.Containerfile"
      "distrobox.ini"
    ];
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
    EDITOR = "hx";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
