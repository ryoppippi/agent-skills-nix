# Build test bundle with prepend, append, and packages options
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
in
agentLib.mkBundle {
  inherit pkgs;
  selection = testSelection;
  name = "agent-skills-test-bundle";
}
