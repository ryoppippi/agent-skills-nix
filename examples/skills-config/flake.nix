{
  description = "skills catalog (child flake example)";

  inputs = {
    anthropic-skills.url = "github:anthropics/skills";
  };

  outputs = { self, anthropic-skills, ... }:
    {
      homeManagerModules.default = { ... }: {
        programs.agent-skills = {
          sources.anthropic = {
            path = anthropic-skills.outPath;
            subdir = "skills";
          };
          skills.enable = [ "frontend-design" "skill-creator" ];
        };
      };
    };
}
