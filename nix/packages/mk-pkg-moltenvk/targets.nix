# MoltenVK-ios.tar contains an ios-arm64 slice only. Registering just this
# target keeps the other four (iossimulator-arm64, iossimulator-amd64,
# macos-arm64, macos-amd64) untouched and buildable with the existing
# OpenGL-only configuration.
let
  oses = import ../../utils/constants/oses.nix;
  archs = import ../../utils/constants/archs.nix;
in
[
  {
    os = oses.ios;
    arch = archs.arm64;
  }
]
