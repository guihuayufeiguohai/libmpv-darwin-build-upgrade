# MoltenVK runtime, unpacked from the official prebuilt releases.
#
# This package does NOT compile anything. MoltenVK ships a static library and a
# dynamic framework per platform slice; it provides everything a cross-built
# mpv/libplacebo needs to find Vulkan at configure/link time:
#
#   $out/lib/libMoltenVK.a                static Vulkan implementation
#   $out/include/vulkan/*                 Vulkan-Headers (from the MoltenVK release)
#   $out/include/vk_video/*               Vulkan video headers
#   $out/include/MoltenVK/*               MoltenVK extensions (VK_MVK_moltenvk)
#   $out/lib/pkgconfig/vulkan.pc          makes meson's dependency('vulkan') work
#   $out/MoltenVK.xcframework             dynamic framework, embed in the app
#   $out/MoltenVK-static.xcframework      static alternative
#   $out/LICENSE.MoltenVK                 Apache-2.0
#
# Slice availability in the v1.4.2 release tarballs:
#   MoltenVK-ios.tar    -> static + dynamic, ios-arm64 ONLY
#                          (no ios-arm64_x86_64-simulator slice -> Vulkan is
#                          not available in the simulator with this tarball;
#                          switching to MoltenVK-all.tar would add it)
#   MoltenVK-macos.tar  -> static + dynamic, macos-arm64_x86_64 (universal)
#                          (its sha256 matches mpv_kit's deps.sh pin)
{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  name = "moltenvk";
  lock = import ../../../packages.lock.nix;
  oses = import ../../utils/constants/oses.nix;

  isMacos = os == oses.macos;
  packageLock = if isMacos then lock.moltenvk-macos else lock.moltenvk;
  inherit (packageLock) version;

  # The .pc Version field must describe the Vulkan API, not the MoltenVK
  # release: mpv asks for dependency('vulkan', version: '>= 1.3.238') and
  # mpv_kit's deps.sh writes Version: $VK_SDK for the same reason.
  vulkanVersion = lock.vulkan-sdk-headers.version;

  callPackage = pkgs.lib.callPackageWith {
    inherit pkgs os arch;
  };
  pname = import ../../utils/name/package.nix name;

  src = callPackage ../../utils/fetch-tarball/default.nix {
    # Include os: the iOS and macOS tarballs share the 1.4.2 version number but
    # have different contents/hashes, and a shared store name makes the CI logs
    # impossible to read.
    name = "${pname}-source-${os}-${version}";
    inherit (packageLock) url sha256;
  };

  # Directory name inside both MoltenVK.xcframework variants. iOS has a single
  # device slice; macOS ships one universal arm64+x86_64 slice.
  staticSlice = if isMacos then "macos-arm64_x86_64" else "ios-arm64";
in

pkgs.runCommand "${pname}-${os}-${arch}-${version}" { } ''
  mkdir -p $out/lib/pkgconfig $out/include

  # fetch-tarball uses --strip-components=1, so the archive's inner
  # MoltenVK/ directory is now at the root of ${src}.
  cp ${src}/MoltenVK/static/MoltenVK.xcframework/${staticSlice}/libMoltenVK.a \
     $out/lib/libMoltenVK.a

  cp -r ${src}/MoltenVK/include/vulkan    $out/include/vulkan
  cp -r ${src}/MoltenVK/include/vk_video  $out/include/vk_video
  cp -r ${src}/MoltenVK/include/MoltenVK  $out/include/MoltenVK

  cp -r ${src}/MoltenVK/static/MoltenVK.xcframework \
        $out/MoltenVK-static.xcframework
  cp -r ${src}/MoltenVK/dynamic/MoltenVK.xcframework \
        $out/MoltenVK.xcframework
  cp ${src}/LICENSE $out/LICENSE.MoltenVK

  # MoltenVK exports the whole Vulkan API, so libmpv links it directly instead
  # of resolving vkGetInstanceProcAddr from the host process at runtime.
  # Quoted ''${...} keeps pkg-config's own variable syntax intact through Nix
  # string interpolation.
  {
    echo "prefix=$out"
    echo 'includedir=''${prefix}/include'
    echo 'libdir=''${prefix}/lib'
    echo ""
    echo "Name: Vulkan"
    echo "Description: MoltenVK ${staticSlice} (statically linked)"
    echo "Version: ${vulkanVersion}"
    echo 'Libs: -L''${libdir} -lMoltenVK'
    echo 'Cflags: -I''${includedir}'
  } > $out/lib/pkgconfig/vulkan.pc

  # Fail loudly if the archive layout ever changes.
  test -f $out/lib/libMoltenVK.a
  test -f $out/include/vulkan/vulkan_core.h
  test -f $out/MoltenVK.xcframework/${staticSlice}/MoltenVK.framework/MoltenVK
  test -f $out/MoltenVK-static.xcframework/${staticSlice}/libMoltenVK.a
''
