{
  description = "Home Manager configuration of gray";

  # for llm-agents binary cache below
  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://zed.cachix.org"
      "https://helix.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "zed.cachix.org-1:/pHQ6dpMsAZk2DiP4WCL0p9YDNKWj2Q5FL20bNmw1cU="
      "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
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

    zed = {
      url = "git+file:///var/home/gray/git/zed?shallow=1&rev=f7ca86e6eeabd135645c4f25aa1ae83f5cf0231b";
    };

    patchmark = {
      url = "git+https://radicle.dpc.pw/z3sP3WnHgo1UfwmfmFM9a5cZSSEZR.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helix = {
      # url = "github:helix-editor/helix";
      url = "github:mattwparas/helix?rev=4d86612df48447088ef4190bf503fd54a7562aa9";
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
        opencode2 = llm-agent-pkgs.opencode2;
        # colgrep = next-plaid-pkgs.colgrep;
        zed = inputs.zed.packages.${system}.default;
        patchmark = inputs.patchmark.packages.${system}.default;
        helix = inputs.helix.packages.${system}.default;
      };
    in
    {
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
