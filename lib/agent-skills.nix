{ lib, inputs }:

let
  inherit (builtins)
    attrNames
    elem
    filter
    foldl'
    hasAttr
    isBool
    isList
    match
    pathExists
    readDir
    ;

  inherit (lib)
    concatMap
    concatMapStringsSep
    filterAttrs
    mapAttrs
    unique
    ;

  inherit (lib.strings)
    hasInfix
    hasPrefix
    ;

  # Resolve the root path for a source, preferring an explicit path and
  # falling back to a flake input name.
  resolveSourceRoot = name: cfg:
    if cfg ? path then cfg.path else
    if cfg ? input then
      if inputs ? ${cfg.input} then inputs.${cfg.input}.outPath
      else throw "agent-skills: source ${name} refers to unknown input ${cfg.input}"
    else throw "agent-skills: source ${name} must set either `path` or `input`";

  # Validate skill IDs so we do not create unsafe paths.
  assertSkillId = id:
    if hasPrefix "/" id || hasInfix ".." id then
      throw "agent-skills: invalid skill id ${id} (must not start with '/' or contain '..')"
    else id;

  # Recursively search for SKILL.md directories up to `maxDepth`.
  discoverSource = name: cfg:
    let
      skillsRoot' = resolveSourceRoot name cfg + "/${cfg.subdir or "."}";
      skillsRoot = if !pathExists skillsRoot' then
        throw "agent-skills: source ${name} subdir ${toString skillsRoot'} does not exist"
      else skillsRoot';

      maxDepth = cfg.filter.maxDepth or 1;
      nameRegex = cfg.filter.nameRegex or null;

      scan = path: relParts: depth:
        let
          entries = readDir path;
          relPath = lib.concatStringsSep "/" relParts;
          hasSkill = entries ? "SKILL.md";
          include = hasSkill && (nameRegex == null || match nameRegex relPath != null);
          current =
            if include then [
              {
                id = assertSkillId (if relPath == "" then name else relPath);
                source = name;
                relPath = relPath;
                absPath = path;
                meta = {};
              }
            ] else [];

          dirs = concatMap (n:
            if entries.${n} == "directory" || entries.${n} == "symlink" then [ n ] else []
          ) (attrNames entries);

          deeper =
            if depth < maxDepth then
              concatMap (n: scan (path + "/${n}") (relParts ++ [ n ]) (depth + 1)) dirs
            else [];
        in current ++ deeper;

      collected = scan skillsRoot [] 0;
    in
    lib.listToAttrs (map (skill: {
      name = skill.id;
      value = skill;
    }) collected);

  # Merge catalogs across sources, enforcing unique IDs.
  discoverCatalog = sources:
    let
      addSource = acc: name: cfg:
        let local = discoverSource name cfg;
        in lib.attrsets.foldlAttrs
          (inner: id: skill:
            if inner ? ${id} then
              throw "agent-skills: duplicate skill id ${id} from ${skill.source} and ${inner.${id}.source}"
            else inner // { ${id} = skill; }
          )
          acc
          local;
    in lib.attrsets.foldlAttrs addSource {} sources;

  # Build allowlist from enableAll + explicit enable list.
  allowlistFor = { catalog, sources, enableAll ? false, enable ? [] }:
    let
      enableAllSources =
        if isList enableAll then enableAll else [];
      enableAllAllSources =
        if isBool enableAll then enableAll else false;
      _ =
        let
          unknown = filter (name: !(hasAttr name sources)) enableAllSources;
        in
        if unknown != [] then
          throw "agent-skills: skills.enableAll refers to unknown sources: ${lib.concatStringsSep ", " unknown}"
        else null;
      sourceAllowlist =
        concatMap (sourceName:
          attrNames (filterAttrs (_: skill: skill.source == sourceName) catalog)
        ) enableAllSources;
    in
    unique (
      (if enableAllAllSources then attrNames catalog else [])
      ++ sourceAllowlist
      ++ enable
    );

  # Build selection from allowlist + explicit skills.
  selectSkills = { catalog, allowlist ? [], skills ? {}, sources }:
    let
      allowlisted = lib.listToAttrs (map (id: {
        name = id;
        value =
          if catalog ? ${id} then catalog.${id}
          else throw "agent-skills: allowlist refers to unknown skill ${id}";
      }) allowlist);

      explicit = filterAttrs (_: cfg: cfg.enable or true) skills;

      fromExplicit = mapAttrs (name: cfg:
        let
          srcName = cfg.from or (throw "agent-skills: skill ${name} must set `from`");
          sourceCfg =
            if sources ? ${srcName} then sources.${srcName}
            else throw "agent-skills: skill ${name} references missing source ${srcName}";
          srcRoot = resolveSourceRoot srcName sourceCfg;
          subdir = sourceCfg.subdir or ".";
          rel = cfg.path or name;
          absPath = srcRoot + "/" + subdir + "/" + rel;
          _ = if !pathExists absPath then
            throw "agent-skills: skill ${name} path ${absPath} does not exist"
          else if !pathExists (absPath + "/SKILL.md") then
            throw "agent-skills: skill ${name} at ${absPath} is missing SKILL.md"
          else null;
          id = assertSkillId (cfg.rename or name);
        in {
          inherit id absPath;
          relPath = rel;
          source = srcName;
          meta = cfg.meta or {};
        }
      ) explicit;

    in
    lib.attrsets.foldlAttrs
      (acc: id: skill:
        if acc ? ${id} then
          throw "agent-skills: skill id collision for ${id}"
        else acc // { ${id} = skill // { inherit id; }; }
      )
      allowlisted
      fromExplicit;

  # Filter targets by enabled flag and system selector.
  targetsFor = { targets, system }:
    filterAttrs (_: t:
      let systems = t.systems or [];
      in (t.enable or true) && (systems == [] || elem system systems)
    ) targets;

  # Materialize bundle in the store, preserving nested paths.
  mkBundle = { pkgs, selection, name ? "agent-skills-bundle" }:
    let
      skills = map (id: selection.${id} // { inherit id; }) (attrNames selection);
      buildCommands = concatMapStringsSep "\n" (skill: ''
        dest=${skill.id}
        mkdir -p "$out/$(dirname "$dest")"
        ln -s ${skill.absPath} "$out/$dest"
      '') skills;
    in
    pkgs.runCommand name { preferLocalBuild = true; } ''
      mkdir -p "$out"
      ${buildCommands}
    '';

  # Render catalog in a stable, JSON-friendly form.
  catalogJson = catalog:
    lib.mapAttrs (_: skill: {
      source = skill.source;
      relPath = skill.relPath;
      absPath = skill.absPath;
      meta = skill.meta or {};
    }) catalog;

  # Default local targets for project-local skill installation.
  # Uses relative paths for project-local installation (not global env vars).
  defaultLocalTargets = {
    codex = { dest = ".codex/skills"; };
    claude = { dest = ".claude/skills"; };
  };

  # Create a local install script for use in consumer flakes.
  # This allows projects to install skills to their local directory.
  # Safety: Only overwrites if destination is a symlink to Nix store or doesn't exist.
  mkLocalInstallScript = { pkgs, bundle, targets ? defaultLocalTargets }:
    let
      dests = builtins.concatStringsSep " " (map (t: t.dest) (builtins.attrValues targets));
    in
    pkgs.writeShellApplication {
      name = "skills-install-local";
      runtimeInputs = [ pkgs.rsync pkgs.coreutils ];
      text = ''
        root="''${AGENT_SKILLS_ROOT:-$PWD}"
        dests="${dests}"
        if [ -n "''${AGENT_SKILLS_LOCAL_DESTS:-}" ]; then
          dests="$AGENT_SKILLS_LOCAL_DESTS"
        fi
        bundle=${bundle}
        if [ ! -d "$bundle" ]; then
          echo "agent-skills: bundle not built" >&2
          exit 1
        fi

        # Check if path is safe to overwrite (doesn't exist, or is a symlink to Nix store)
        is_safe_to_overwrite() {
          local path="$1"
          if [ ! -e "$path" ]; then
            return 0  # Doesn't exist, safe
          fi
          if [ -L "$path" ]; then
            local target
            target="$(readlink -f "$path")"
            if [[ "$target" == /nix/store/* ]]; then
              return 0  # Symlink to Nix store, safe
            fi
          fi
          return 1  # Not safe
        }

        for dest in $dests; do
          if [ -z "$dest" ]; then continue; fi
          full_dest="$root/$dest"

          if ! is_safe_to_overwrite "$full_dest"; then
            echo "agent-skills: $full_dest exists and is not a Nix-managed path" >&2
            echo "agent-skills: skipping to avoid overwriting user data" >&2
            echo "agent-skills: remove manually or set AGENT_SKILLS_FORCE=1 to overwrite" >&2
            if [ "''${AGENT_SKILLS_FORCE:-}" != "1" ]; then
              continue
            fi
            echo "agent-skills: AGENT_SKILLS_FORCE=1 set, overwriting anyway" >&2
          fi

          mkdir -p "$(dirname "$full_dest")"
          rm -rf "$full_dest"
          ln -s "$bundle" "$full_dest"
          echo "agent-skills: installed to $full_dest"
        done
      '';
    };

  # Create a shellHook string for use in devShells.
  # Automatically installs skills when entering the dev shell.
  mkShellHook = { pkgs, bundle, targets ? defaultLocalTargets }:
    let
      installScript = mkLocalInstallScript { inherit pkgs bundle targets; };
    in ''
      ${installScript}/bin/skills-install-local
    '';

in
{
  discoverCatalog = discoverCatalog;
  selectSkills = selectSkills;
  allowlistFor = allowlistFor;
  targetsFor = targetsFor;
  mkBundle = mkBundle;
  catalogJson = catalogJson;
  mkLocalInstallScript = mkLocalInstallScript;
  mkShellHook = mkShellHook;
  defaultLocalTargets = defaultLocalTargets;
}
