let
  oses = import ../../utils/constants/oses.nix;
  archs = import ../../utils/constants/archs.nix;
in
[
  { os = oses.macos; arch = archs.arm64; }
  { os = oses.ios; arch = archs.arm64; }
]
