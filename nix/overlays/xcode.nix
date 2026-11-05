# Override Xcode package to link to a custom version.
#
# If a custom Xcode path is set in .nix/config/xcode.path, it will be used
# directly instead of fetching Xcode from the Nix store.
#
# Usage example (see Makefile):
#   make build-flake XCODE_PATH=/Applications/Xcode_16.1.0.app
#
# ===========================================================================
# How to download a specific Xcode version
# ===========================================================================
# See https://github.com/NixOS/nixpkgs/blob/24.05/pkgs/os-specific/darwin/xcode/default.nix
#
# ===========================================================================
# How to get Xcode version
# ===========================================================================
#   $ /path/to/Xcode.app/Contents/Developer/usr/bin/xcodebuild -version
#   Xcode 16.0
#   Build version 16A242d
#
# ===========================================================================
# How to store Xcode and prevent it from being garbage collected
# ===========================================================================
#   $ nix-store --add-fixed --recursive sha256 /path/to/Xcode.app
#   /nix/store/9irb2b36sn0693q7x2l554inm81vb2g6-Xcode.app
#   $ sudo mkdir -m 0755 /nix/var/nix/gcroots/per-user/$USER
#   $ sudo chown -R $USER /nix/var/nix/gcroots/per-user/$USER
#   $ ln -s /nix/store/9irb2b36sn0693q7x2l554inm81vb2g6-Xcode.app /nix/var/nix/gcroots/per-user/$USER/xcode-16-0
#
# ===========================================================================
# How to get base64 hash of Xcode object
# ===========================================================================
#   $ nix-store --query --hash /nix/store/9irb2b36sn0693q7x2l554inm81vb2g6-Xcode.app
#   sha256:0bi8wpdji34zypsl1d4hyickd8i35pd063cmvnldd22lyk2gpsz3
#   $ nix hash convert --to base64 sha256:0bi8wpdji34zypsl1d4hyickd8i35pd063cmvnldd22lyk2gpsz3
#   4+v7xPRUiNao3ZUNA9otI6I2WfSQtED19Z+MKNvlKC4=
#
# ===========================================================================
# How to allow Xcode to be garbage collected
# ===========================================================================
#   $ rm /nix/var/nix/gcroots/per-user/$USER/xcode-16-0
#
final: prev: {
  darwin = prev.darwin.overrideScope (
    self: super:
    let
      requireXcode =
        version: sha256:
        prev.requireFile rec {
          name = "Xcode.app";
          url = "https://developer.apple.com/services-account/download?path=/Developer_Tools/Xcode_${version}/Xcode_${version}.xip";
          hashMode = "recursive";
          inherit sha256;
          message = ''
            Download Xcode ${version} from ${url} and run:
            nix-store --add-fixed --recursive sha256 Xcode.app
          '';
        };
    in
    {
      xcode_16_1 = requireXcode "16.1" "sha256-yYg6NRRnYM/5X3hhVMfcXcdoiOV36fIongJNQ5nviD8=";

      xcode =
        let
          xcodePath = prev.lib.trim (builtins.readFile ../../.nix/config/xcode.path);
        in
        if xcodePath != "" then xcodePath else self.xcode_16_1;
    }
  );
}
