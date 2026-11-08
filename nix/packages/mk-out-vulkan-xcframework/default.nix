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
# One xcframework is produced per dylib in libmpv's runtime closure:
#   Mpv       libmpv (libplacebo + glslang + MoltenVK are static inside it)
#   Avcodec, Avformat, Avutil, Avfilter, Swresample, Swscale, Ass, Uchardet,
#   Harfbuzz, Fribidi, Freetype, Png, Mbedtls, Dav1d, Xml2
# That mirrors the OpenGL build (which ships the same closure as frameworks)
# and avoids the LGPL question that statically linking FFmpeg would raise.
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

  # libmpv links these as @rpath dylibs, and their own install names are
  # absolute /nix/store paths. Without rewriting them (see buildPhase) the
  # resulting Mpv.framework/Mpv keeps
  #   /nix/store/...-mk-pkg-ffmpeg-.../lib/libavcodec.62.dylib
  # style dependencies, which do not exist on a device -> dyld aborts on
  # launch. libplacebo, glslang and MoltenVK are already statically linked
  # into libmpv, so they are deliberately absent here.
  ffmpeg8 = callPackage ../mk-pkg-ffmpeg8/default.nix {
    variant = "video";
    flavor = "default";
  };
  mbedtls = callPackage ../mk-pkg-mbedtls/default.nix { inherit os arch; };
  dav1d = callPackage ../mk-pkg-dav1d/default.nix { inherit os arch; };
  libxml2 = callPackage ../mk-pkg-libxml2/default.nix { inherit os arch; };
  uchardet = callPackage ../mk-pkg-uchardet/default.nix { inherit os arch; };
  libass = callPackage ../mk-pkg-libass/default.nix { inherit os arch; };
  harfbuzz = callPackage ../mk-pkg-harfbuzz/default.nix { inherit os arch; };
  fribidi = callPackage ../mk-pkg-fribidi/default.nix { inherit os arch; };
  freetype = callPackage ../mk-pkg-freetype/default.nix { inherit os arch; };
  libpng = callPackage ../mk-pkg-libpng/default.nix { inherit os arch; };

  # Same closure the OpenGL build ships, minus libplacebo (static here).
  deps = [
    mpvVulkan
    ffmpeg8
    mbedtls
    dav1d
    libxml2
    uchardet
    libass
    harfbuzz
    fribidi
    freetype
    libpng
  ];

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

    # Collect the whole runtime closure. Same normalisation the OpenGL build's
    # mk-out-libs does, and it is mandatory here: build-*.sh only rewrites
    # dependencies that already start with @rpath, while the libraries below
    # record absolute /nix/store/... paths as their install names.
    for dep in ${pkgs.lib.concatStringsSep " " deps}; do
      find "$dep/lib" -type f -name '*.dylib' ! -name '*-subset.*.dylib' \
        -exec cp {} ./deps/ \;
    done

    # libfoo.100.99.88.dylib -> libfoo.dylib (one framework per library)
    for file in ./deps/lib*.dylib; do
      new_path=$(echo "$file" | sed -E 's/^(.*\/lib[^.]*).*$/\1.dylib/')
      if [ "$file" != "$new_path" ]; then mv "$file" "$new_path"; fi
    done

    # install name: libfoo.dylib -> @rpath/libfoo.dylib
    for file in ./deps/lib*.dylib; do
      install_name_tool -id "@rpath/$(basename "$file")" "$file"
    done

    # dependency: /nix/store/**/libfoo.99.dylib -> @rpath/libfoo.99.dylib
    for file in ./deps/lib*.dylib; do
      deps_list=$(otool -L "$file" | tail -n +3 | sed -n 's|.*\(/nix/store/[^ ]*\).*|\1|p')
      for dep in $deps_list; do
        install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$file"
      done
    done

    # dependency: @rpath/libfoo.99.dylib -> @rpath/libfoo.dylib
    for file in ./deps/lib*.dylib; do
      deps_list=$(otool -L "$file" | tail -n +3 | sed -n 's|.*\(@rpath/[^ ]*\).*|\1|p')
      for dep in $deps_list; do
        name=$(echo "$dep" | sed -n 's|@rpath/\(lib[^.]*\).*|\1.dylib|p')
        install_name_tool -change "$dep" "@rpath/$name" "$file"
      done
    done

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
    # Fail loudly if the packaging silently produced nothing, or if a
    # dependency escaped the framework conversion.
    test -d $out/Mpv.xcframework
    test -d $out/Uchardet.xcframework
    test -d $out/Avcodec.xcframework
    test -d $out/Ass.xcframework
    # No dylib may still point at a Nix store path.
    if otool -L $out/Mpv.xcframework/*/Mpv.framework/Mpv \
        $out/Mpv.xcframework/*/Mpv.framework/Versions/A/Mpv 2>/dev/null \
        | grep -q '/nix/store/'; then
      echo "error: Mpv still depends on Nix store paths" >&2
      otool -L $out/Mpv.xcframework/*/Mpv.framework/Mpv >&2 || true
      exit 1
    fi
  '';
}
