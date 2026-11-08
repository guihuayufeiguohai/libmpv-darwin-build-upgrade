# Packs the Vulkan libmpv bundle into XCFrameworks that media-kit can vendor
# directly.
#
# media_kit's libs podspec declares
#   s.vendored_frameworks = 'Frameworks/*.xcframework'
# and its create_framework_symlinks.sh derives the per-slice symlinks
# (ios -> ios-arm64, ios-simulator -> ios-arm64_x86_64-simulator) from the
# directory names inside Mpv.xcframework. So the output must be real
# XCFrameworks, not bare dylibs.
#
# Two frameworks are produced:
#   Mpv.xcframework       libmpv (libplacebo + glslang + MoltenVK static)
#   Uchardet.xcframework  libuchardet, which libmpv links as @rpath dylib
# Keeping Uchardet separate (instead of statically linking it into libmpv)
# matches how the OpenGL build ships its dependency closure and avoids the
# C++ runtime (-lc++) link dance a static uchardet would need.
#
# The dylib -> framework conversion reuses the OpenGL build's scripts
# verbatim: they derive "Mpv" from libmpv.2.dylib and "Uchardet" from
# libuchardet.dylib, rewrite install names and inter-framework dependencies,
# strip Nix-store LC_RPATHs, write Info.plist and, for Mpv, add
# Headers/ + Modules/ with an umbrella Mpv.h.
{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  oses = import ../../utils/constants/oses.nix;
  callPackage = pkgs.lib.callPackageWith {
    inherit pkgs os arch;
  };

  mpvVulkan = callPackage ../mk-out-vulkan/default.nix { inherit os arch; };
  uchardet = callPackage ../mk-pkg-uchardet/default.nix { inherit os arch; };

  xctoolchainInstallNameTool = callPackage ../../utils/xctoolchain/install-name-tool.nix { };
  xctoolchainLipo = callPackage ../../utils/xctoolchain/lipo.nix { };
  xctoolchainOtool = callPackage ../../utils/xctoolchain/otool.nix { };
  xctoolchainPlutil = callPackage ../../utils/xctoolchain/plutil.nix { };
  xctoolchainVtool = callPackage ../../utils/xctoolchain/vtool.nix { };
  xctoolchainXcodebuild = callPackage ../../utils/xctoolchain/xcodebuild.nix { };

  # Verbatim reuse of the OpenGL build's framework scripts (macOS needs the
  # Versions/A layout, iOS is flat).
  buildScript =
    if os == oses.macos then
      callPackage ../../utils/patch-shebangs/default.nix {
        name = "mk-out-vulkan-xcframework-build-macos.sh";
        src = ../mk-out-frameworks/macos/build-macos.sh;
      }
    else
      callPackage ../../utils/patch-shebangs/default.nix {
        name = "mk-out-vulkan-xcframework-build-ios.sh";
        src = ../mk-out-frameworks/ios/build-ios.sh;
      };

  # mpv public headers from the VULKAN build: mk-pkg-mpv-vulkan installs
  # render_vk.h, which the baseline mk-pkg-mpv does not. The build script
  # copies only *.h into the framework, so the Vulkan headers are added
  # separately below.
  mpvHeaders = pkgs.runCommand "mpv-vulkan-headers" { } ''
    mkdir -p $out
    cp ${mpvVulkan}/include/mpv/*.h $out/
    test -f $out/render_vk.h
  '';
in

pkgs.stdenvNoCC.mkDerivation {
  name = "vulkan-xcframework-${os}-${arch}";
  dontUnpack = true;
  enableParallelBuilding = true;
  nativeBuildInputs = [
    xctoolchainInstallNameTool
    xctoolchainLipo
    xctoolchainOtool
    xctoolchainPlutil
    xctoolchainVtool
    xctoolchainXcodebuild
    # build-*.sh uses `bc -l` to compare min OS versions across slices.
    pkgs.bc
  ];
  buildPhase = ''
    mkdir -p deps build

    # Only the real versioned objects: build-*.sh globs `-type f`, while the
    # unversioned names inside the bundle are symlinks.
    cp ${mpvVulkan}/lib/libmpv.2.dylib deps/
    cp ${uchardet}/lib/libuchardet.dylib deps/

    export DEPS=$PWD/deps
    export OUTPUT_DIR=$PWD/build
    export MPV_HEADERS_PATH=${mpvHeaders}
    export MPV_MODULE_MAP_PATH=${../mk-out-frameworks/common/mpv/module.modulemap}
    ${if os == oses.macos then ''
      export INFO_PLIST_PATH=${../mk-out-frameworks/macos/Info.plist}
    '' else ''
      export INFO_PLIST_PATH=${../mk-out-frameworks/ios/Info.plist}
    ''}

    ${buildScript}

    # render_vk.h does `#include <vulkan/vulkan.h>`; clang resolves that
    # against the framework's Headers dir when the app does `import Mpv`.
    # macOS keeps headers under Versions/A/Headers (Headers is a symlink).
    ${if os == oses.macos then ''
      MPV_HDR=build/Mpv.framework/Versions/A/Headers
    '' else ''
      MPV_HDR=build/Mpv.framework/Headers
    ''}
    mkdir -p "$MPV_HDR/vulkan" "$MPV_HDR/vk_video"
    cp -r ${mpvVulkan}/include/vulkan/. "$MPV_HDR/vulkan/"
    cp -r ${mpvVulkan}/include/vk_video/. "$MPV_HDR/vk_video/"
    test -f "$MPV_HDR/render_vk.h"
    test -f "$MPV_HDR/vulkan/vulkan_core.h"

    # One xcframework per framework; a single slice is valid.
    for fw in build/*.framework; do
      name=$(basename "$fw" .framework)
      xcodebuild -create-xcframework -framework "$fw" \
        -output "build/$name.xcframework"
    done
  '';
  installPhase = ''
    mkdir -p $out
    cp -r build/*.xcframework $out/
    # Fail loudly if the packaging silently produced nothing.
    test -d $out/Mpv.xcframework
    test -d $out/Uchardet.xcframework
  '';
}
