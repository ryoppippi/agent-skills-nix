# Test for prepend, append, and packages options
{ pkgs, agentLib }:

let
  prependContent = builtins.readFile ./fixtures/prepend.md;
  appendContent = builtins.readFile ./fixtures/append.md;

  testSources = {
    test-fixtures = {
      path = ./fixtures/test-skill;
    };
  };

  testCatalog = agentLib.discoverCatalog testSources;

  testSelection = agentLib.selectSkills {
    catalog = testCatalog;
    allowlist = [];
    sources = testSources;
    skills = {
      test-skill = {
        from = "test-fixtures";
        path = ".";
        prepend = prependContent;
        append = appendContent;
        packages = [ pkgs.jq pkgs.curl ];
      };
    };
  };

  testBundle = agentLib.mkBundle {
    inherit pkgs;
    selection = testSelection;
    name = "agent-skills-test-bundle";
  };
in
pkgs.runCommand "agent-skills-prepend-append-packages-test" {} ''
  set -e
  skillMd="${testBundle}/test-skill/SKILL.md"

  # Check file exists
  test -f "$skillMd" || { echo "SKILL.md not found"; exit 1; }

  # Check Dependencies table exists (from packages) with local paths
  grep -q "## Dependencies" "$skillMd" || { echo "Dependencies section not found"; exit 1; }
  grep -q "| jq | \`./jq\` |" "$skillMd" || { echo "jq package not found with local path in table"; exit 1; }
  grep -q "| curl | \`./curl\` |" "$skillMd" || { echo "curl package not found with local path in table"; exit 1; }

  # Check symlinks to package binaries exist
  skillDir="${testBundle}/test-skill"
  test -L "$skillDir/jq" || { echo "jq symlink not found"; exit 1; }
  test -L "$skillDir/curl" || { echo "curl symlink not found"; exit 1; }

  # Check symlinks point to Nix store and are executable
  jq_target=$(readlink -f "$skillDir/jq")
  curl_target=$(readlink -f "$skillDir/curl")
  [[ "$jq_target" == /nix/store/* ]] || { echo "jq symlink does not point to Nix store"; exit 1; }
  [[ "$curl_target" == /nix/store/* ]] || { echo "curl symlink does not point to Nix store"; exit 1; }

  # Check commands are executable
  "$skillDir/jq" --version > /dev/null || { echo "jq is not executable"; exit 1; }
  "$skillDir/curl" --version > /dev/null || { echo "curl is not executable"; exit 1; }

  # Check prepend content (from fixtures/prepend.md)
  grep -q "# Prepended Content" "$skillMd" || { echo "Prepended content not found"; exit 1; }
  grep -q "This was prepended." "$skillMd" || { echo "Prepended text not found"; exit 1; }

  # Check original content (from fixtures/test-skill/SKILL.md)
  grep -q "# Test Skill" "$skillMd" || { echo "Original content not found"; exit 1; }

  # Check append content (from fixtures/append.md)
  grep -q "# Appended Content" "$skillMd" || { echo "Appended content not found"; exit 1; }
  grep -q "This was appended." "$skillMd" || { echo "Appended text not found"; exit 1; }

  # Check order: Dependencies -> Prepend -> Original -> Append
  deps_line=$(grep -n "## Dependencies" "$skillMd" | head -1 | cut -d: -f1)
  prepend_line=$(grep -n "# Prepended Content" "$skillMd" | head -1 | cut -d: -f1)
  original_line=$(grep -n "# Test Skill" "$skillMd" | head -1 | cut -d: -f1)
  append_line=$(grep -n "# Appended Content" "$skillMd" | head -1 | cut -d: -f1)

  test "$deps_line" -lt "$prepend_line" || { echo "Dependencies should come before prepend"; exit 1; }
  test "$prepend_line" -lt "$original_line" || { echo "Prepend should come before original"; exit 1; }
  test "$original_line" -lt "$append_line" || { echo "Original should come before append"; exit 1; }

  echo "All tests passed!"
  mkdir -p "$out"
  touch "$out/ok"
''
