{
  inputs,
  lib,
  ...
}: let
  l = lib // builtins;
in {
  type = "pure";

  build = {
    lib,
    pkgs,
    stdenv,
    # dream2nix inputs
    externals,
    utils,
    ...
  }: {
    ### FUNCTIONS
    # AttrSet -> Bool) -> AttrSet -> [x]
    getCyclicDependencies, # name: version: -> [ {name=; version=; } ]
    getDependencies, # name: version: -> [ {name=; version=; } ]
    getSource, # name: version: -> store-path
    # to get information about the original source spec
    getSourceSpec, # name: version: -> {type="git"; url=""; hash="";}
    ### ATTRIBUTES
    subsystemAttrs, # attrset
    defaultPackageName, # string
    defaultPackageVersion, # string
    # all exported (top-level) package names and versions
    # attrset of pname -> version,
    packages,
    # all existing package names and versions
    # attrset of pname -> versions,
    # where versions is a list of version strings
    packageVersions,
    # function which applies overrides to a package
    # It must be applied by the builder to each individual derivation
    # Example:
    #   produceDerivation name (mkDerivation {...})
    produceDerivation,
    ...
  } @ args: let
    b = builtins;

    # the main package
    defaultPackage = allPackages."${defaultPackageName}"."${defaultPackageVersion}";

    # packages to export
    packages =
      lib.mapAttrs
      (name: version: {
        "${version}" = allPackages.${name}.${version};
      })
      args.packages;

    # manage packages in attrset to prevent duplicated evaluation
    allPackages =
      lib.mapAttrs
      (name: versions:
        lib.genAttrs
        versions
        (version: makeOnePackage name version))
      packageVersions;

    # Generates a derivation for a specific package name + version
    makeOnePackage = name: version: let
      pkg = pkgs.haskell.packages.ghc8107.mkDerivation (rec {
          pname = utils.sanitizeDerivationName name;
          inherit version;
          license = null;

          src = getSource name version;

          isLibrary = true;
          isExecutable = true;
          doCheck = false;
          doBenchmark = false;

          libraryToolDepends = libraryHaskellDepends;
          executableHaskellDepends = libraryHaskellDepends;
          testHaskellDepends = libraryHaskellDepends;
          testToolDepends = libraryHaskellDepends;

          libraryHaskellDepends =
            # TODO: use ghc version from subsystemAttrs
            (with pkgs.haskell.packages.ghc8107; [
              # TODO: remove these deps / find out why they were missing
              hspec
              QuickCheck
            ])
            ++ (
              map
              (dep: allPackages."${dep.name}"."${dep.version}")
              (getDependencies name version)
            );

          # TODO: Implement build phases
        }
        /*
        For all transitive dependencies, overwrite cabal file with the one
        from all-cabal-json.
        We want to ensure that the cabal file is the latest revision.
        See: https://github.com/haskell-infra/hackage-trustees/blob/master/revisions-information.md
        */
        // (l.optionalAttrs (name != defaultPackageName) {
          preConfigure = ''
            cp ${inputs.all-cabal-json}/${name}/${version}/${name}.cabal ./
          '';
        })
        # enable tests only for the top-level package
        // (l.optionalAttrs (name == defaultPackageName) {
          doCheck = true;
        }));
    in
      # apply packageOverrides to current derivation
      produceDerivation name pkg;
  in {
    inherit defaultPackage packages;
  };
}
