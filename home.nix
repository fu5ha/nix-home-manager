{ config, pkgs, llm-agent-pkgs, username, homeDirectory, ... }:
let
  customPkgs = import ./pkgs/custom.nix {inherit pkgs username;};
  customPackages = with customPkgs; [
      fedoraHost
  ];

  nixPackages = with pkgs; [
    nushell
    htop
    jq
    just
    alejandra
    gh
    jujutsu
    jjui
    starship
    jj-starship
    zoxide
    eza
    fnm
    radicle-node
    radicle-tui
    radicle-desktop
  ];

  llmPackages = with llm-agent-pkgs; [
    pi
  ];

  homeManagerConfigDir = pkgs.lib.path.append (/. + homeDirectory) ".config/home-manager";

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

  home.packages = nixPackages ++ customPackages ++ llmPackages;
  
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
      ui.default-command = ["log"];
      revsets.log = "@ | ancestors(trunk()..(visible_heads() & mine()), 8) | ancestors(trunk(), 3)";
    };
  };

  programs.jjui = {
    enable = true;
  };

  programs.radicle = {
    enable = true;
  };

  services.radicle.node = {
    enable = false;
  };

  programs.nushell = {
    enable = true;
    configFile.source = ./nushell/config.nu;

    shellAliases = {
      hmc = "^($env.config.buffer_editor) ~/.config/home-manager";
    };
  };

  programs.starship = {
    enable = true;
    enableNushellIntegration = true;
    settings = {
      custom = {
        jj = {
          when = "jj-starship detect";
          shell = "jj-starship";
          format = "$output ";
        };
      };
      git_branch.disabled = true;
      git_status.disabled = true;
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
      "distrobox" = {
        recursive = true;
        source = ./distrobox;
      };
    };
    # copy to ~/.local/share
    dataFile = {
      
    };
  };

  hostConfig = {
    enable = true;

    xdgDesktopEntries = true;

    files = [
      ".config/distrobox/distrobox.conf"
      ".config/distrobox/containers.ini"
      ".config/git/config"
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
