{
  lib,
  dlib,
  dream2nixInterface,
  pkgs,
  ...
} @ topArgs: let
  l = lib // builtins;
  defaultMkPackagesFromDreamLock = dreamLock:
    (dream2nixInterface.makeOutputsForDreamLock {
      inherit dreamLock;
    })
    .packages;
  generatePackagesFromLocks = {
    dreamLocks,
    makePackagesForDreamLock ? defaultMkPackagesFromDreamLock,
  }:
    l.foldl'
    (acc: el: acc // el)
    {}
    (l.map makePackagesForDreamLock dreamLocks);
in rec {
  generatePackagesFromLocksTree = {
    source ? throw "pass source",
    tree ? dlib.prepareSourceTree {inherit source;},
    makePackagesForDreamLock ? defaultMkPackagesFromDreamLock,
  }: let
    findDreamLocks = tree:
      (
        let
          dreamLockFile = tree.files."dream-lock.json" or {};
        in
          l.optional
          (
            dreamLockFile
            ? content
            && l.stringLength dreamLockFile.content > 0
          )
          dreamLockFile.jsonContent
      )
      ++ (
        l.flatten (
          l.map findDreamLocks
          (l.attrValues tree.directories)
        )
      );
    dreamLocks = findDreamLocks tree;
  in
    generatePackagesFromLocks {
      inherit dreamLocks makePackagesForDreamLock;
    };
  makeOutputsForIndexes = {
    source,
    indexNames,
    extendOutputs ? args: prevOutputs: {},
  }: let
    l = lib // builtins;
    mkApp = script: {
      type = "app";
      program = toString script;
    };

    mkIndexApp = {
      name,
      input,
    } @ args: let
      input = {outputFile = "${name}/index.json";} // args.input;
      script = pkgs.writers.writeBash "index" ''
        set -e
        inputJson="$(${pkgs.coreutils}/bin/mktemp)"
        echo '${l.toJSON input}' > $inputJson
        ${d2n.apps.index}/bin/index ${name} $inputJson
      '';
    in
      mkApp script;
    mkTranslateApp = name:
      mkApp (
        pkgs.writers.writeBash "translate-${name}" ''
          set -e
          ${d2n.apps.translate-index}/bin/translate-index \
            ${name}/index.json ${name}/locks
        ''
      );
    translateApps = l.listToAttrs (
      l.map
      (
        name:
          l.nameValuePair
          "translate-${name}"
          (mkTranslateApp name)
      )
      indexNames
    );
    translateAllApp = let
      allTranslators =
        l.concatStringsSep
        "\n"
        (
          l.mapAttrsToList
          (
            name: translator: ''
              echo "::translating with ${name}::"
              ${translator}
              echo "::translated with ${name}::"
            ''
          )
          translateApps
        );
    in
      mkApp (
        pkgs.writers.writeBash "translate-all" ''
          set -e
          ${allTranslators}
        ''
      );

    mkIndexOutputs = name:
      if l.pathExists "${source}/${name}/locks"
      then
        l.removeAttrs
        (generatePackagesFromLocksTree {
          source = l.path {
            name = "${name}";
            path = "${source}/${name}/locks";
          };
        })
        ["default"]
      else {};

    allPackages =
      l.foldl'
      (acc: el: acc // el)
      {}
      (l.map mkIndexOutputs indexNames);

    outputs = {
      packages = allPackages;
      apps =
        translateApps
        // {
          translate = translateAllApp;
        };
    };
  in
    outputs // (extendOutputs topArgs outputs);
}