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
        overlays = [
          # TEMPORARY (Oct 2026, eMudhra intermediate CA compromise,
          # CVE-2026-111943): nixos-unstable still ships cacert 3.126,
          # which trusts the roots cross-signing the compromised
          # intermediates. Blacklist the same roots NixOS master drops
          # in its security.ca defaults. Remove this overlay once the
          # locked nixpkgs has cacert >= 3.131.1; test with:
          #   curl --cacert "$(nix build --no-link --print-out-paths .#homeConfigurations.gray.pkgs.cacert)/etc/ssl/certs/ca-bundle.crt" https://dv-g3b-emudhra.we-have-a-problem.com/
          # (must fail with a certificate error). Note this does not
          # cover tools that embed their own roots (Node/Electron apps,
          # some Rust binaries) or non-Nix runtimes (brew/fnm Node, uv).
          (_final: prev: {
            cacert = prev.cacert.override {
              blacklist = [
                "Comodo AAA Services root"
                "emSign ECC Root CA - G3"
                "emSign Root CA - C1"
                "emSign ECC Root CA - C3"
              ];
            };
          })
        ];
      };

      llm-agent-pkgs = inputs.llm-agents.packages.${system};
      # next-plaid-pkgs = (inputs.next-plaid.lib.mkPackagesWithCudaCapabilities [ "7.5" ]).${system};
      
      extra-pkgs = {
        pi = llm-agent-pkgs.pi;
        codex = llm-agent-pkgs.codex;
        muse-code = llm-agent-pkgs.muse-code;
        claude-code = llm-agent-pkgs.claude-code;
        # llm-agents' t3code, with our providers baked into the wrapper
        # PATH instead of upstream's defaults (which omit pi and include
        # cursor-agent/grok/opencode-1.x). Build standalone with
        # `nix build .#t3code`.
        t3code = llm-agent-pkgs.t3code.override {
          providerPackages = [
            llm-agent-pkgs.pi
            llm-agent-pkgs.codex
            llm-agent-pkgs.claude-code
          ];
        };
        # colgrep = next-plaid-pkgs.colgrep;
        # patchmark = inputs.patchmark.packages.${system}.default;
        helix = inputs.helix.packages.${system}.default;
        zed = inputs.zed.packages.${system}.default;
      };
    in
    {
      packages.${system}.t3code = extra-pkgs.t3code;

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
