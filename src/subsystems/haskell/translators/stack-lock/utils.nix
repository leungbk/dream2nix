{
  lib,
  dlib,
  pkgs,
}: let
  l = lib // builtins;

  flakeCompat = import (builtins.fetchTarball {
    url = "https://github.com/edolstra/flake-compat/tarball/b4a34015c698c7793d592d66adbab377907a2be8";
    sha256 = "1qc703yg0babixi6wshn5wm2kgl5y1drcswgszh4xxzbrwkk9sv7";
  });
in rec {
  # The cabal2json program
  cabal2json = pkgs.haskell.packages.ghc8107.cabal2json;

  # parse cabal file via IFD
  fromCabal = file: name: let
    file' = l.path {path = file;};
    jsonFile = pkgs.runCommandLocal "${name}.cabal.json" {} ''
      ${cabal2json}/bin/cabal2json ${file'} > $out
    '';
  in
    l.fromJSON (l.readFile jsonFile);

  # fromYaml IFD implementation
  fromYaml = file: let
    file' = l.path {path = file;};
    jsonFile = pkgs.runCommandLocal "yaml.json" {} ''
      ${pkgs.yaml2json}/bin/yaml2json < ${file'} > $out
    '';
  in
    l.fromJSON (l.readFile jsonFile);
}
