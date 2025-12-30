{ inputs, lib, ... }:

let
  agentLibFor = inputsFromArgs:
    import ../../lib/agent-skills.nix {
      inherit lib;
      inputs = inputs // inputsFromArgs;
    };
in
{ config, pkgs, lib, ... }@args:
let
  cfg = config.programs.agent-skills;
  agentLib = agentLibFor (args.inputs or {});

  activeTargets = agentLib.targetsFor { targets = cfg.targets; system = pkgs.system; };

  linkTargets = lib.filterAttrs (_: t: t.structure == "link") activeTargets;
  syncTargets = lib.filterAttrs (_: t: t.structure != "link") activeTargets;

  assertDest = dest:
    if lib.strings.hasPrefix "/" dest then
      throw "agent-skills: target destination must be home-relative, got ${dest}"
    else dest;

  syncScript = bundle: ''
    bundle=${bundle}
    if [ ! -d "$bundle" ]; then
      echo "agent-skills: bundle not found at $bundle" >&2
      exit 1
    fi
  '' + lib.concatStringsSep "\n" (lib.mapAttrsToList (_: t:
    let
      dest = "$HOME/${assertDest t.dest}";
      syncCmd = if t.structure == "copy-tree" then
        ''${pkgs.rsync}/bin/rsync -aL --delete "${bundle}/" "${dest}/"''
      else
        ''${pkgs.rsync}/bin/rsync -a --delete "${bundle}/" "${dest}/"'';
    in ''
      mkdir -p "${dest}"
      ${syncCmd}
    ''
  ) syncTargets);
in
{
  imports = [ (import ../common.nix { inherit inputs lib; }) ];

  config = lib.mkIf cfg.enable (let
    bundle = cfg.bundlePath;
  in {
    home.activation.agent-skills =
      lib.mkIf (syncTargets != {}) (lib.hm.dag.entryAfter [ "writeBoundary" ] (syncScript bundle));

    home.file = lib.mkMerge (lib.mapAttrsToList (_: t: {
      ${assertDest t.dest} = {
        source = bundle;
        recursive = true;
        force = true;
      };
    }) linkTargets);
  });
}
