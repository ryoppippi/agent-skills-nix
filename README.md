# Agent Skills Nix Framework

Declarative management of Agent Skills (directories containing `SKILL.md`) with flake-pinned sources, discovery, selection, bundling, and Home Manager integration.

## Concepts

- **sources**: Named inputs (flake or path) pointing at a skills root (`subdir`).
- **discover**: Scans sources for directories that contain `SKILL.md`, producing a catalog.
- **skills.enable / skills.explicit**: Declaratively pick discovered skills and explicitly specified ones; no accidental auto-install.
- **targets**: Agent-specific destinations synced from a store bundle (structure: `link`, `symlink-tree`, `copy-tree`).

## Quick start (child flake + Home Manager)

Put skills config in a small child flake so the only pinned inputs there are skill sources.

`skills/flake.nix` (child, same directory as `home-manager.nix`):
```nix
{
  description = "skills catalog";

  inputs = {
    anthropic-skills.url = "github:anthropics/skills";
    anthropic-skills.flake = false;
  };

  outputs = { self, anthropic-skills, ... }:
    {
      homeManagerModules.default =
        import ./home-manager.nix { inherit anthropic-skills; };
    };
}
```

`skills/home-manager.nix` (child):
```nix
{ anthropic-skills, ... }:
{
  programs.agent-skills = {
    sources.anthropic = {
      path = anthropic-skills;
      subdir = "skills";
    };
    skills.enable = [ "frontend-design" "skill-creator" ];
  };
}
```

Then load it from your main Home Manager config:

```nix
{ inputs, ... }:
{
  imports = [
    inputs.agent-skills.homeManagerModules.default
    inputs.skills-config.homeManagerModules.default
  ];

  programs.agent-skills = {
    enable = true;
    targets = {
      codex  = { dest = ".codex/skills";  structure = "symlink-tree"; };
      claude = { dest = ".claude/skills"; structure = "symlink-tree"; };
    };
  };
}
```

Notes:

- If you use a child flake, import both modules: `inputs.agent-skills.homeManagerModules.default` and `inputs.skills-config.homeManagerModules.default`.
- Pass your flake `inputs` to Home Manager (e.g. `home-manager.extraSpecialArgs = { inherit inputs; };`) so source `input` names resolve.
- `structure = "link"` uses `home.file` symlinks; `symlink-tree` and `copy-tree` run in `home.activation`.
- `symlink-tree` uses `rsync -a --delete` (preserve symlinks); `copy-tree` uses `rsync -aL --delete` (dereference symlinks).
- Examples live at `examples/child-flake/flake.nix`, `examples/child-flake/home-manager.nix`, `examples/direct/flake.nix`, and `examples/direct/home-manager.nix`.

## Flake outputs

- `packages.<system>.agent-skills-bundle`: Store bundle of selected skills (empty by default; configure in consumers).
- `apps.<system>.skills-install`: Sync bundle to default targets (`$HOME/.codex/skills`, `$HOME/.claude/skills`). Override destinations with `AGENT_SKILLS_DESTS`.
- `apps.<system>.skills-list`: JSON view of the default catalog.
- `checks.<system>.skills`: Sanity check that the bundle builds.
- `homeManagerModules.default`: Home Manager module implementing the DSL above.
- `lib.agent-skills`: Helper functions (`discoverCatalog`, `selectSkills`, `mkBundle`, `catalogJson`, `defaultConfig`).

## Library functions

```nix
let
  lib = (import ./lib/agent-skills.nix { inherit inputs; lib = nixpkgs.lib; });
  catalog = lib.discoverCatalog sources;
  selection = lib.selectSkills { inherit catalog sources; allowlist = [ "foo" ]; skills = { bar = { from = "local"; path = "bar"; }; }; };
  bundle = lib.mkBundle { pkgs = nixpkgs.legacyPackages.${system}; selection = selection; };
in { inherit catalog selection bundle; }
```

`discoverCatalog` enforces `SKILL.md` presence and rejects duplicate IDs. `selectSkills` errors on unknown allowlist entries or missing files, preventing accidental drift. (Home Manager maps `skills.enable` → `allowlist` and `skills.explicit` → `skills`.)

## Apps usage

- List catalog: `nix run .#skills-list`
- Sync bundle: `nix run .#skills-install` (override destinations via `AGENT_SKILLS_DESTS="~/tmp/skills1 ~/tmp/skills2"`)

Both apps operate on the flake’s default (empty) config; point at your own flake/module for real catalogs.

## Checks / safety

- Disallows skill IDs containing `/..` or leading `/`.
- Verifies `SKILL.md` for discovered and explicit skills.
- Fails on duplicate IDs across sources.
- Activation scripts always `mkdir -p` and use `rsync -a --delete` by default.
