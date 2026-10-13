{
  description = "Home Manager configuration of gray";

  # for llm-agents binary cache below
  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://helix.cachix.org"
      "https://zed.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
      "zed.cachix.org-1:/pHQ6dpMsAZk2DiP4WCL0p9YDNKWj2Q5FL20bNmw1cU="
    ];
  };

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # for pi
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    # Lock release metadata so `nix flake update` also updates desktop nightlies.
    t3code-releases = {
      url = "file+https://api.github.com/repos/pingdotgg/t3code/releases?per_page=100";
      flake = false;
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # next-plaid = {
    #   url = "github:lightonai/next-plaid";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    patchmark = {
      url = "git+https://radicle.dpc.pw/z3sP3WnHgo1UfwmfmFM9a5cZSSEZR.git";
    };

    helix = {
      # url = "github:helix-editor/helix";
      url = "github:mattwparas/helix?rev=4d86612df48447088ef4190bf503fd54a7562aa9";
    };

    autolith = {
      url = "github:lambda-symbolics/autolith";
    };

    # Local checkout of fu5ha/zed so fork changes can land without a push.
    # Advance with `nix flake update zed` after moving the jj-inbox-fork
    # bookmark; no nixpkgs follows, the fork builds against its locked nixpkgs.
    zed = {
      url = "git+file:///home/gray/git/zed?ref=jj-inbox-fork";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      ...
    } @ inputs :
    let
      system = "x86_64-linux";
      
      pkgs = import nixpkgs {
        inherit system;
      };

      llm-agent-pkgs = inputs.llm-agents.packages.${system};
      # next-plaid-pkgs = (inputs.next-plaid.lib.mkPackagesWithCudaCapabilities [ "7.5" ]).${system};
      
      extra-pkgs = {
        pi = llm-agent-pkgs.pi;
        codex = llm-agent-pkgs.codex;
        muse-code = llm-agent-pkgs.muse-code;
        opencode2 = llm-agent-pkgs.opencode2;
        t3code-desktop = pkgs.callPackage ./lib/t3code-nightly.nix {
          releasesFile = inputs.t3code-releases;
        };
        # From-source nightly build (fork of numtide/llm-agents.nix t3code).
        # Build standalone with `nix build .#t3code-src`. See
        # lib/t3code/unwrapped.nix for how to bump the nightly.
        t3code-src = pkgs.callPackage ./lib/t3code/package.nix {
          t3code-unwrapped = pkgs.callPackage ./lib/t3code/unwrapped.nix {
            formatelf = pkgs.callPackage ./lib/t3code/formatelf.nix { };
            versionCheckHomeHook =
              pkgs.callPackage ./lib/t3code/versionCheckHomeHook/package.nix { };
          };
          providerPackages = [
            llm-agent-pkgs.pi
            llm-agent-pkgs.codex
          ];
        };
        # colgrep = next-plaid-pkgs.colgrep;
        # patchmark = inputs.patchmark.packages.${system}.default;
        helix = inputs.helix.packages.${system}.default;
        autolith = inputs.autolith.packages.${system}.default;
        zed = inputs.zed.packages.${system}.default;
      };
    in
    {
      packages.${system}.t3code-src = extra-pkgs.t3code-src;

      homeConfigurations."gray" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          inputs.nix-index-database.homeModules.default
          ./home.nix
        ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
        extraSpecialArgs = {
          extra-pkgs = extra-pkgs;
        };
      };
    };
}
