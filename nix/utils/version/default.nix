{
  pkgs ? import ../default/pkgs.nix,
}:

pkgs.lib.trim (builtins.readFile ../../../.nix/config/version.txt)
