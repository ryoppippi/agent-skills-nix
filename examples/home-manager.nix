# Minimal Home Manager snippet for agent-skills-nix consumers.
{ inputs, ... }:
{
  # Ensure your flake passes `inputs` into Home Manager (extraSpecialArgs).
  imports = [
    inputs.agent-skills.homeManagerModules.default
    inputs.skills-config.homeManagerModules.default
  ];

  programs.agent-skills = {
    enable = true;
    targets = {
      codex  = { dest = ".codex/skills";  method = "rsync"; };
      claude = { dest = ".claude/skills"; method = "rsync"; };
    };
  };
}
