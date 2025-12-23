{
  description = "direct Home Manager example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    agent-skills.url = "path:../..";
    anthropic-skills.url = "github:anthropics/skills";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
    let
      system = builtins.currentSystem;
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations.example = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home-manager.nix ];
        extraSpecialArgs = { inherit inputs; };
      };
    };
}
