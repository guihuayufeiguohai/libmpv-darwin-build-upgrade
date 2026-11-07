# Same API as `builtins.fetchTarball`, but two hashing modes are supported:
#
#   sha256  - hash of the *non-extracted* tarball, not the NAR hash once
#             decompressed (legacy mode, used by most entries in
#             packages.lock.nix; verified via builtins.fetchurl).
#
#   narHash - NAR hash of the *extracted* tree (SRI string, e.g.
#             "sha256-..."), i.e. the same hashing scheme used by
#             `fetchFromGitHub` / `fetchzip` / `nix-prefetch-url --unpack`.
#             This lets us pin sources whose upstream file hash is hard to
#             obtain but whose NAR hash is published authoritatively (for
#             example nixpkgs' `mpv-unwrapped` entry).
#
#   mirrors - optional list of extra URLs tried (in order) if the primary
#             `url` fails to download. Useful for flaky upstream hosts such
#             as ffmpeg.org. The same `sha256`/`narHash` must match whichever
#             URL actually serves the file.
#
# Exactly one of `sha256` / `narHash` must be supplied.
{
  pkgs ? import ../../utils/default/pkgs.nix,
  name,
  url,
  sha256 ? null,
  narHash ? null,
  mirrors ? [ ],
}:
if (sha256 == null) == (narHash == null) then
  throw "fetch-tarball: exactly one of `sha256` or `narHash` must be set for ${name}"
else if narHash != null then
  # Extracts the tarball and strips the single top-level directory, matching
  # the `--strip-components=1` behaviour of the legacy branch below.
  pkgs.fetchzip {
    inherit name;
    urls = [ url ] ++ mirrors;
    hash = narHash;
    stripRoot = true;
  }
else
  let
    tarball = pkgs.fetchurl {
      inherit name;
      urls = [ url ] ++ mirrors;
      sha256 = sha256;
    };
  in
  pkgs.runCommand name { } ''
    mkdir $out
    tar -xvf ${tarball} --strip-components=1 -C $out
  ''
