{
  pkgs
}:
let
  lib = pkgs.lib;
in
  pkgs.rustPlatform.buildRustPackage (finalAttrs: {
    pname = "colgrep";
    version = "1.3.0";

    buildNoDefaultFeatures = true;
    buildFeatures = [ "cuda" ];
    buildAndTestSubdir = "colgrep";

    nativeBuildInputs = [
      pkgs.pkg-config
      pkgs.curl
    ];

    buildInputs = [
      pkgs.cudaPackages.cudatoolkit
      pkgs.cudaPackages.cudnn
      pkgs.openssl
      pkgs.curl
    ];

    src = pkgs.fetchFromGitHub {
      owner = "lightonai";
      repo = "next-plaid";
      tag = "v1.3.0";
      hash = "sha256-5h9m8fGgPraShHC4p+QIhXil2RqJr720HHcBfWFLoGQ=";
    };

    cargoHash = "sha256-/xs79CFFb3y4zPyR8xgUOUBI6HV6nENZh2ttPRyH5mY=";
      
    meta = {
      description = "Semantic code search powered by ColBERT";
      homepage = "https://github.com/lightonai/next-plaid/tree/main/colgrep";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  })


