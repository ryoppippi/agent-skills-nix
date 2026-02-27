# Test mkLocalInstallScript behavior around copy-tree overwrite safety.
{ pkgs, agentLib }:

let
  testSources = {
    test-skill = {
      path = ./fixtures/test-skill;
    };
  };

  testCatalog = agentLib.discoverCatalog testSources;
  testAllowlist = agentLib.allowlistFor {
    catalog = testCatalog;
    sources = testSources;
    enableAll = true;
  };
  testSelection = agentLib.selectSkills {
    catalog = testCatalog;
    allowlist = testAllowlist;
    skills = {};
    sources = testSources;
  };
  testBundle = agentLib.mkBundle {
    inherit pkgs;
    selection = testSelection;
    name = "agent-skills-test-local-install-bundle";
  };
  installScript = agentLib.mkLocalInstallScript {
    inherit pkgs;
    bundle = testBundle;
    targets = {
      codex = {
        dest = ".codex/skills";
        structure = "copy-tree";
        enable = true;
        systems = [];
      };
    };
  };
in
pkgs.runCommand "agent-skills-local-install-script-test" {} ''
  set -euo pipefail

  project="$PWD/project"
  mkdir -p "$project/.codex/skills"
  echo "sentinel" > "$project/.codex/skills/EXISTING.txt"

  (
    cd "$project"
    "${installScript}/bin/skills-install-local"
  ) > "$PWD/install.log" 2>&1

  test -f "$project/.codex/skills/test-skill/SKILL.md" || {
    echo "ERROR: copy-tree should install into an existing directory target"
    echo "---- install.log ----"
    cat "$PWD/install.log"
    echo "---------------------"
    exit 1
  }

  echo "copy-tree installed successfully into pre-existing directory"
  mkdir -p "$out"
  touch "$out/ok"
''
