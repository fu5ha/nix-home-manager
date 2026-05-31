{
  description = "Home Manager configuration of gray";

  # for llm-agents binary cache below
  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-config = {
      url = "github:thrix/nix-config";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # for pi
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    next-plaid = {
      url = "github:lightonai/next-plaid";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zed = {
      url = "git+file:///home/gray/git/zed?shallow=1";
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
      next-plaid-pkgs = (inputs.next-plaid.lib.mkPackagesWithCudaCapabilities [ "7.5" ]).${system};
      
      extra-pkgs = {
        pi = llm-agent-pkgs.pi;
        colgrep = next-plaid-pkgs.colgrep;
        zed = inputs.zed.packages.${system}.default;
      };
    in
    {
      homeConfigurations."gray" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          inputs.nix-index-database.homeModules.default
          inputs.nix-config.homeManagerModules.hostConfig
          ./home.nix
        ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
        extraSpecialArgs = {
          extra-pkgs = extra-pkgs;
          username = "gray";
          homeDirectory = "/home/gray";
        };
      };
    };
}
