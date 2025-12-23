{
  description = "Declarative Agent Skills management with flake-pinned sources and Home Manager integration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
    let
      lib = nixpkgs.lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = lib.genAttrs systems;
      agentLib = import ./lib/agent-skills.nix { inherit lib inputs; };

      defaultTargets = {
        codex = { dest = ".codex/skills"; method = "rsync"; enable = true; systems = []; };
        claude = { dest = ".claude/skills"; method = "rsync"; enable = true; systems = []; };
      };

      defaultConfig = {
        # Add sources and skills (enable/explicit) in your consumer flake; kept empty here to stay neutral.
        sources = {};
        skills = {
          enable = [];
          explicit = {};
        };
        targets = defaultTargets;
      };

      defaultCatalog = agentLib.discoverCatalog defaultConfig.sources;
      defaultSelection = agentLib.selectSkills {
        catalog = defaultCatalog;
        allowlist = defaultConfig.skills.enable;
        skills = defaultConfig.skills.explicit;
        sources = defaultConfig.sources;
      };

      targetsFor = system:
        lib.filterAttrs (_: t: t.enable && (t.systems == [] || builtins.elem system t.systems)) defaultTargets;

      defaultDests = system:
        builtins.concatStringsSep " "
          (map (t: "$HOME/${t.dest}") (builtins.attrValues (targetsFor system)));

      bundleFor = system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        agentLib.mkBundle { inherit pkgs; selection = defaultSelection; name = "agent-skills-bundle"; };
    in
    {
      packages = forAllSystems (system: let
        bundle = bundleFor system;
      in {
        agent-skills-bundle = bundle;
        default = bundle;
      });

      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          bundle = bundleFor system;
          dests = defaultDests system;
          listJson = pkgs.writeText "agent-skills-catalog.json" (builtins.toJSON (agentLib.catalogJson defaultCatalog));

          installScript = pkgs.writeShellApplication {
            name = "skills-install";
            runtimeInputs = [ pkgs.rsync pkgs.coreutils ];
            text = ''
              dests="${dests}"
              if [ -n "$AGENT_SKILLS_DESTS" ]; then
                dests="$AGENT_SKILLS_DESTS"
              fi
              bundle=${bundle}
              if [ ! -d "$bundle" ]; then
                echo "agent-skills: bundle not built" >&2
                exit 1
              fi
              for dest in $dests; do
                if [ -z "$dest" ]; then continue; fi
                mkdir -p "$dest"
                ${pkgs.rsync}/bin/rsync -a --delete "${bundle}/" "$dest/"
              done
            '';
          };

          listScript = pkgs.writeShellApplication {
            name = "skills-list";
            runtimeInputs = [ pkgs.jq pkgs.coreutils ];
            text = ''
              cat ${listJson} | ${pkgs.jq}/bin/jq .
            '';
          };
        in {
          skills-install = {
            type = "app";
            program = "${installScript}/bin/skills-install";
          };
          skills-list = {
            type = "app";
            program = "${listScript}/bin/skills-list";
          };
        });

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          bundle = bundleFor system;
        in {
          skills = pkgs.runCommand "agent-skills-checks" {} ''
            test -d ${bundle}
            mkdir -p "$out"
            touch "$out/ok"
          '';
        });

      homeManagerModules.default =
        import ./modules/home-manager/agent-skills.nix { inherit inputs lib; };

      lib.agent-skills = agentLib // { defaultConfig = defaultConfig; };
      catalog = agentLib.catalogJson defaultCatalog;
    };
}
