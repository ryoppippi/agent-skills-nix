# Direct Home Manager configuration (no child flake).
{ inputs, ... }:
{
  imports = [ inputs.agent-skills.homeManagerModules.default ];

  programs.agent-skills = {
    enable = true;
    sources = {
      anthropic = { input = "anthropic-skills"; subdir = "skills"; };
    };
    skills.enable = [ "frontend-design" "skill-creator" ];
    targets = {
      codex  = { dest = ".codex/skills";  structure = "symlink-tree"; };
      claude = { dest = ".claude/skills"; structure = "symlink-tree"; };
    };
  };
}
