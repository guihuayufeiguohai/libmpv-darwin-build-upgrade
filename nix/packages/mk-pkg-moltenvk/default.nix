# MoltenVK iOS runtime, unpacked from the official prebuilt release.
#
# This package does NOT compile anything: MoltenVK ships a static library and
# a dynamic framework for ios-arm64 only (there is no simulator slice in
# MoltenVK-ios.tar). It provides everything a cross-built mpv/libplacebo needs
# to find Vulkan at configure/link time:
#
#   $out/lib/libMoltenVK.a                 static Vulkan 1.3 implementation
#   $out/include/vulkan/*                 Vulkan-Headers 1.3.357 (>= mpv's 1.3.238)
#   $out/include/vk_video/*               Vulkan video headers
#   $out/include/MoltenVK/*               MoltenVK extensions (VK_MVK_moltenvk)
#   $out/lib/pkgconfig/vulkan.pc          makes meson's dependency('vulkan') work
#   $out/MoltenVK.xcframework             dynamic framework, embed in the app
#   $out/MoltenVK-static.xcframework      static alternative
#   $out/LICENSE.MoltenVK                 Apache-2.0
#
# NOTE: because the binary is ios-arm64 only, targets.nix registers this
# package for ios-arm64 exclusively. Never enable -Dvulkan for
# iossimulator-* or macos-* targets with this dependency.
{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  name = "moltenvk";
  packageLock = (import ../../../packages.lock.nix).${name};
  inherit (packageLock) version;

  callPackage = pkgs.lib.callPackageWith {
    inherit pkgs os arch;
  };
  pname = import ../../utils/name/package.nix name;

  src = callPackage ../../utils/fetch-tarball/default.nix {
    name = "${pname}-source-${version}";
    inherit (packageLock) url sha256;
  };
in

pkgs.runCommand "${pname}-${os}-${arch}-${version}" { } ''
  mkdir -p $out/lib/pkgconfig $out/include

  # fetch-tarball uses --strip-components=1, so the archive's inner
  # MoltenVK/ directory is now at the root of ${src}.
  cp ${src}/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a \
     $out/lib/libMoltenVK.a

  cp -r ${src}/MoltenVK/include/vulkan    $out/include/vulkan
  cp -r ${src}/MoltenVK/include/vk_video  $out/include/vk_video
  cp -r ${src}/MoltenVK/include/MoltenVK  $out/include/MoltenVK

  cp -r ${src}/MoltenVK/dynamic/MoltenVK.xcframework \
        $out/MoltenVK.xcframework
  cp -r ${src}/MoltenVK/static/MoltenVK.xcframework \
        $out/MoltenVK-static.xcframework
  cp ${src}/LICENSE $out/LICENSE.MoltenVK

  # MoltenVK exports the whole Vulkan API, so libmpv links it directly.
  # A .pc file is enough for mpv's `dependency('vulkan', version: '>=1.3.238')`
  # and for libplacebo's pkg-config lookup. Quoted ''${...} keeps pkg-config's
  # own variable syntax intact through Nix string interpolation.
  {
    echo "prefix=$out"
    echo 'includedir=''${prefix}/include'
    echo 'libdir=''${prefix}/lib'
    echo ""
    echo "Name: Vulkan"
    echo "Description: MoltenVK (iOS arm64, statically linked)"
    echo "Version: ${version}"
    echo 'Libs: -L''${libdir} -lMoltenVK'
    echo 'Cflags: -I''${includedir}'
  } > $out/lib/pkgconfig/vulkan.pc

  # Fail loudly if the archive layout ever changes.
  test -f $out/lib/libMoltenVK.a
  test -f $out/include/vulkan/vulkan_core.h
  test -f $out/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK
''
