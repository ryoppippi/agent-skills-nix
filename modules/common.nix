{ inputs, lib, ... }:

let
  agentLibFor = inputsFromArgs:
    import ../lib/agent-skills.nix {
      inherit lib;
      inputs = inputs // inputsFromArgs;
    };
in
{ config, pkgs, ... }@args:
let
  cfg = config.programs.agent-skills;
  agentLib = agentLibFor (args.inputs or {});

  targetType = lib.types.submodule ({ config, ... }: {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Synchronise this target.";
      };

      dest = lib.mkOption {
        type = lib.types.str;
        description = "Destination relative to $HOME (e.g. .codex/skills).";
      };

      structure = lib.mkOption {
        type = lib.types.enum [ "link" "symlink-tree" "copy-tree" ];
        default = "symlink-tree";
        description = "How the target is laid out (link, symlink-tree, or copy-tree).";
      };

      systems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Limit to specific system identifiers; empty means all.";
      };
    };
  });

  sourceType = lib.types.submodule ({ ... }: {
    options = {
      input = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Flake input name providing this source.";
      };

      path = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Local path fallback instead of `input`.";
      };

      subdir = lib.mkOption {
        type = lib.types.str;
        default = ".";
        description = "Subdirectory under the input/path that contains skills.";
      };

      filter = {
        maxDepth = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Recursion depth when discovering SKILL.md directories.";
        };

        nameRegex = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional regex to restrict discovered skills.";
        };
      };
    };
  });

  skillType = lib.types.submodule ({ name, ... }: {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to include this explicit skill.";
      };

      from = lib.mkOption {
        type = lib.types.str;
        description = "Source name providing the skill.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Relative path under the source's subdir.";
      };

      rename = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Expose under a different ID in the bundle.";
      };

      meta = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
        description = "Optional metadata override.";
      };
    };
  });
in
{
  options.programs.agent-skills = {
    enable = lib.mkEnableOption "Declarative Agent Skills management.";

    sources = lib.mkOption {
      type = lib.types.attrsOf sourceType;
      default = {};
      description = "Named skill sources (flake input or path).";
    };

    skills = lib.mkOption {
      type = lib.types.submodule ({ ... }: {
        options = {
          enable = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Skill IDs to enable from discovered catalog.";
            example = [ "format-pr" "nix-review" ];
          };

          enableAll = lib.mkOption {
            type = lib.types.either lib.types.bool (lib.types.listOf lib.types.str);
            default = false;
            description = "Enable all discovered skills; set true for all sources or a list of source names.";
          };

          explicit = lib.mkOption {
            type = lib.types.attrsOf skillType;
            default = {};
            description = "Explicitly selected skills with optional rename.";
          };
        };
      });
      default = {
        enable = [];
        enableAll = false;
        explicit = {};
      };
      description = "Skill selection (allowlist + explicit).";
    };

    targets = lib.mkOption {
      type = lib.types.attrsOf targetType;
      default = {};
      description = "Agent-specific sync destinations.";
    };

    catalog = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "Discovered skills catalog.";
    };

    bundlePath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Store path for the built bundle.";
    };
  };

  config = lib.mkIf cfg.enable (let
    catalog = agentLib.discoverCatalog cfg.sources;
    allowlist = agentLib.allowlistFor {
      inherit catalog;
      sources = cfg.sources;
      enableAll = cfg.skills.enableAll;
      enable = cfg.skills.enable;
    };
    selection = agentLib.selectSkills {
      inherit catalog allowlist;
      skills = cfg.skills.explicit;
      sources = cfg.sources;
    };
    bundle = agentLib.mkBundle { inherit pkgs selection; };
  in {
    programs.agent-skills.catalog = catalog;
    programs.agent-skills.bundlePath = bundle;
  });
}
