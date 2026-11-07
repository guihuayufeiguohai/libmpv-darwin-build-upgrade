{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  name = "mpv-vulkan";
  packageLock = (import ../../../packages.lock.nix).mpv;
  inherit (packageLock) version;

  variants = import ../../utils/constants/variants.nix;
  oses = import ../../utils/constants/oses.nix;
  callPackage = pkgs.lib.callPackageWith {
    inherit pkgs os arch;
  };
  nativeFile = callPackage ../../utils/native-file/default.nix { };
  crossFile = callPackage ../../utils/cross-file/default.nix { };
  # mpv's Vulkan gate is
  #   cc.has_header_symbol('vulkan/vulkan_core.h', 'VK_VERSION_1_3',
  #                        dependencies: vulkan)
  # and it returns NO when the SDK include dir is not on the compiler's search
  # path, which silently kills features['vulkan'] -> 'Feature videotoolbox-pl
  # cannot be enabled'. Bake the -I straight into the cross file's built-in
  # options so the probe cannot depend on pkg-config cflags or on env CPATH.
  #
  # CoreVideo hides EVERY Metal type unless the deployment target is at least
  # 10.11 (CoreVideo.framework/Headers/CVBase.h):
  #
  #   #if COREVIDEO_SUPPORTS_IOSURFACE && (TARGET_OS_IPHONE ||
  #           (MAC_OS_X_VERSION_MIN_REQUIRED >= 101100)) && !TARGET_OS_WATCH
  #       #define COREVIDEO_SUPPORTS_METAL COREVIDEO_TRUE
  #   #else
  #       #define COREVIDEO_SUPPORTS_METAL COREVIDEO_FALSE
  #   #endif
  #
  # The stock cross file pins -mmacosx-version-min=10.9, so
  # COREVIDEO_SUPPORTS_METAL evaluates to FALSE, CVMetalTextureCache.h is never
  # pulled in, and hwdec_vt_pl.m dies with
  #   hwdec_vt.h:53:5: error: unknown type name 'CVMetalTextureCacheRef'
  #   hwdec_vt.h:54:5: error: unknown type name 'CVMetalTextureRef'
  #
  # 11.0 is the real floor for arm64 macOS, so nothing is lost. iOS is
  # unaffected: there TARGET_OS_IPHONE short-circuits the same check. Only the
  # Vulkan cross file is rewritten - the OpenGL build keeps its 10.9 floor.
  macosDeploymentTargetFix = pkgs.lib.optionalString (os == oses.macos) ''
    sed -i 's/-mmacosx-version-min=10\.9/-mmacosx-version-min=11.0/g' $out
    test "$(grep -c -- '-mmacosx-version-min=11.0' $out)" = "1"
  '';
  crossFileVulkan = pkgs.runCommand "mk-cross-file-${os}-${arch}-vulkan.ini" { } ''
    # NOTE: '#' is the s/// delimiter on purpose - the pattern uses '|' for
    # alternation, so '|' cannot also be the delimiter.
    sed -E "s#^(c_args|cpp_args|objc_args|objcpp_args)( *= *)\[#\1\2['-I${vulkanSdk}/include', #" \
      ${crossFile} > $out
    got=$(grep -c -- "-I${vulkanSdk}/include" $out || true)
    if [ "$got" != "4" ]; then
      echo "cross-file: expected 4 injected -I flags, got $got" >&2
      cat $out >&2
      exit 1
    fi

    ${macosDeploymentTargetFix}
  '';
  xctoolchainLipo = callPackage ../../utils/xctoolchain/lipo.nix { };
  vulkanSdk = callPackage ../mk-pkg-vulkan-sdk/default.nix { inherit os arch; };

  # These dependency packages are wired exactly like the baseline OpenGL
  # mk-pkg-mpv does (callPackage ... { }): no `variant` is forwarded, because
  # libass/uchardet/libbluray/ffmpeg do NOT accept a `variant` argument.
  # Forwarding `variant` here is what broke the stage-2 eval with
  # "function called with unexpected argument 'variant'".
  ffmpeg = callPackage ../mk-pkg-ffmpeg/default.nix { };
  libplacebo = callPackage ../mk-pkg-libplacebo360/default.nix { };
  uchardet = callPackage ../mk-pkg-uchardet/default.nix { };
  libass = callPackage ../mk-pkg-libass/default.nix { };

  nativeBuildInputs = [
    pkgs.meson
    pkgs.ninja
    pkgs.pkg-config
    pkgs.python3
    xctoolchainLipo
  ];

  pname = import ../../utils/name/package.nix name;
  src = callPackage ../../utils/fetch-tarball/default.nix (
    {
      name = "${pname}-source-${version}";
      inherit (packageLock) url;
    }
    // pkgs.lib.optionalAttrs (packageLock ? narHash) { inherit (packageLock) narHash; }
    // pkgs.lib.optionalAttrs (packageLock ? sha256) { inherit (packageLock) sha256; }
  );
  patchedSource = pkgs.runCommand "${pname}-patched-source-${version}" { } ''
    cp -r ${src} src
    export src=$PWD/src
    chmod -R 777 $src

    cd $src
    # Ported to mpv 0.41: audio tap + iOS shared-AVAudioSession refcounting.
    patch -p1 <${../../../patches/mpv-041-audiounit.patch}

    # Ported to mpv 0.41: HTTP/HTTPS Blu-ray streaming + autodetect.
    patch -p1 <${../../../patches/mpv-041-bluray-http.patch}

    # Vulkan render API for vo_libmpv (mpv_kit backends). These are the
    # private MPV_RENDER_API_TYPE_VULKAN extension that media_kit's new
    # TextureHW will drive. They REPLACE the GL renderer-selection patch used
    # by the OpenGL build (that patch conflicts with 0004).
    patch -p1 <${../../../patches/mpv-041-vulkan-0001-render-backend.patch}
    patch -p1 <${../../../patches/mpv-041-vulkan-0002-hwdec-extensions.patch}
    patch -p1 <${../../../patches/mpv-041-vulkan-0004-gpu-next.patch}
    patch -p1 <${../../../patches/mpv-041-vulkan-0005-get-info.patch}

    # Register the Objective-C compiler unconditionally on darwin. mpv gates
    # add_languages('objc') on the macOS SDK probe, which needs xcrun, which
    # the nix sandbox does not have -> hwdec_vt_pl.m was compiled as C and
    # died on 'unknown type name CVMetalTextureCacheRef'.
    patch -p1 <${../../../patches/mpv-041-vulkan-0006-darwin-objc-language.patch}

    cd -

    cp -r $src $out
  '';
  # mpv ships helper scripts invoked by meson itself, most importantly
  # TOOLS/macos-sdk-version.py:
  #   macos_sdk_version_py = find_program(.../TOOLS/macos-sdk-version.py,
  #                                     required: true)
  #   macos_sdk_info = run_command(macos_sdk_version_py, check: true)
  # Its shebang is '#!/usr/bin/env python3', which the nix sandbox cannot
  # resolve, so meson dies with
  #   ERROR: Unhandled python OSError. This is probably not a Meson bug, but
  #   an issue with your build environment.
  # Rewrite every shebang to a store path (same helper the OpenGL build uses).
  fixedSource = callPackage ../../utils/patch-shebangs/default.nix {
    name = "${pname}-fixed-source-${version}";
    src = patchedSource;
    inherit nativeBuildInputs;
  };
in

pkgs.stdenvNoCC.mkDerivation {
  name = "${pname}-${os}-${arch}-${version}";
  pname = pname;
  inherit version;
  src = fixedSource;
  dontUnpack = true;
  enableParallelBuilding = true;
  inherit nativeBuildInputs;
  # libbluray is disabled in the Vulkan build (-Dlibbluray=disabled above), so
  # it is intentionally omitted from buildInputs here.
  # vulkanSdk is a buildInput so nixpkgs' pkg-config wrapper puts its
  # lib/pkgconfig on PKG_CONFIG_PATH: mpv's meson resolves Vulkan exclusively
  # through `dependency('vulkan', version: '>= 1.3.238')`, and without a
  # vulkan.pc that lookup fails silently and Vulkan is dropped from the build.
  buildInputs =
    [ ffmpeg libplacebo libass uchardet vulkanSdk ];
  configurePhase = ''
    set -o pipefail

    export CFLAGS="-I${vulkanSdk}/include $CFLAGS"
    export CXXFLAGS="-I${vulkanSdk}/include $CXXFLAGS"
    # Same reason as libplacebo: make the SDK include dir reachable through the
    # compiler's own search path (CPATH), independent of meson's handling of
    # env CFLAGS in a cross build.
    export CPATH="${vulkanSdk}/include:$CPATH"
    # Belt and braces: the pkg-config wrapper already adds the buildInputs'
    # pkgconfig dirs, but spell the Vulkan SDK out so the lookup cannot depend
    # on setup-hook ordering.
    export PKG_CONFIG_PATH="${vulkanSdk}/lib/pkgconfig:$PKG_CONFIG_PATH"

    DISABLE_ALL_OPTIONS=(
      -Dgpl=false -Dcplayer=false -Dlibmpv=false -Dbuild-date=false
      -Dtests=false -Dfuzzers=false

      -Dcdda=disabled -Dcplugins=disabled -Ddvbin=disabled -Ddvdnav=disabled
      -Diconv=disabled -Djavascript=disabled -Dlcms2=disabled
      -Dlibarchive=disabled -Dlibavdevice=disabled -Dlibbluray=disabled
      -Dlua=disabled -Dpthread-debug=disabled -Drubberband=disabled
      -Dsdl2-gamepad=disabled -Duchardet=disabled -Duwp=disabled
      -Dvapoursynth=disabled -Dvector=disabled -Dwin32-threads=disabled
      -Dx11-clipboard=disabled -Dzimg=disabled -Dzlib=disabled

      -Daaudio=disabled -Dalsa=disabled -Daudiotrack=disabled
      -Daudiounit=disabled -Davfoundation=disabled -Dcoreaudio=disabled
      -Djack=disabled -Dopenal=disabled -Dopensles=disabled -Doss-audio=disabled
      -Dpipewire=disabled -Dpulse=disabled -Dsdl2-audio=disabled
      -Dsndio=disabled -Dwasapi=disabled

      -Dcaca=disabled -Dcocoa=disabled -Dd3d11=disabled -Ddirect3d=disabled
      -Ddrm=disabled -Degl=disabled -Degl-android=disabled -Degl-angle=disabled
      -Degl-angle-lib=disabled -Degl-angle-win32=disabled -Degl-drm=disabled
      -Degl-wayland=disabled -Degl-x11=disabled -Dgbm=disabled
      -Dgl=disabled -Dgl-cocoa=disabled -Dgl-dxinterop=disabled
      -Dgl-win32=disabled -Dgl-x11=disabled -Ddmabuf-wayland=disabled
      -Djpeg=disabled -Dsdl2-video=disabled -Dshaderc=disabled -Dsixel=disabled
      -Dspirv-cross=disabled -Dplain-gl=disabled -Dvdpau=disabled
      -Dvdpau-gl-x11=disabled -Dvaapi=disabled -Dvaapi-drm=disabled
      -Dvaapi-wayland=disabled -Dvaapi-x11=disabled
      # Vulkan context support (the whole point of this build)
      -Dvulkan=enabled
      -Dwayland=disabled -Dx11=disabled -Dxv=disabled

      -Dandroid-media-ndk=disabled -Dcuda-hwaccel=disabled
      -Dcuda-interop=disabled -Dd3d-hwaccel=disabled -Dd3d9-hwaccel=disabled
      -Dgl-dxinterop-d3d9=disabled -Dios-gl=disabled
      # hwdec via libplacebo (VideoToolbox -> Vulkan frames)
      -Dvideotoolbox-gl=disabled -Dvideotoolbox-pl=enabled

      -Dmacos-10-15-4-features=disabled -Dmacos-11-features=disabled
      -Dmacos-11-3-features=disabled -Dmacos-12-features=disabled
      -Dmacos-cocoa-cb=disabled -Dmacos-media-player=disabled
      -Dmacos-touchbar=disabled -Dswift-build=disabled -Dswift-flags=
      -Dhtml-build=disabled -Dmanpage-build=disabled -Dpdf-build=disabled
    )

    COMMON_OPTIONS=(
      -Dlibmpv=true -Dbuild-date=true -Diconv=enabled
    )
    COMMON_VIDEO_OPTIONS=(
      -Duchardet=enabled -Dzlib=enabled
    )

    OPTIONS=("''${DISABLE_ALL_OPTIONS[@]}")
    OPTIONS+=("''${COMMON_OPTIONS[@]}")
    OPTIONS+=("''${COMMON_VIDEO_OPTIONS[@]}")

    if [ "${os}" == "${oses.macos}" ]; then
      # macOS Vulkan route: no Cocoa window / Swift bridging (mpv_kit renders
      # through the Vulkan render API). CoreAudio for sound.
      OPTIONS+=(-Dcoreaudio=enabled)
    elif [ "${os}" == "${oses.ios}" ]; then
      OPTIONS+=(-Daudiounit=enabled)
    fi

    meson setup build $src \
      --native-file ${nativeFile} \
      --cross-file ${crossFileVulkan} \
      --prefix=$out \
      "''${OPTIONS[@]}" |
      tee configure.log || true

    if [ ! -f build/config.h ]; then
      echo "=== meson setup FAILED ===" >&2
      echo "pkg-config --cflags vulkan: $(pkg-config --cflags vulkan 2>&1)" >&2
      echo "CPATH=$CPATH" >&2
      echo "--- vulkan probe as meson ran it ---" >&2
      grep -B8 'vulkan_core.h' build/meson-logs/meson-log.txt 2>/dev/null | tail -n 30 >&2 || true
      exit 1
    fi

    # ---- post-configure assertions --------------------------------------
    # mpv only emits "#define HAVE_<FEATURE> 1" when EVERY prerequisite was
    # found, and it degrades silently: a missing vulkan.pc, or a libplacebo
    # configured without Vulkan (pl_has_vulkan=0 in libplacebo.pc), produces a
    # perfectly "successful" build whose libmpv has no Vulkan render API.
    # Never ship such an artifact - fail here with a readable message instead.
    echo "--- mpv feature summary (vulkan route) ---"
    grep -E '^#define HAVE_(VULKAN|LIBPLACEBO|VIDEOTOOLBOX_PL|GL|EGL|IOS_GL|COCOA) ' \
      build/config.h || true
    for feature in VULKAN LIBPLACEBO VIDEOTOOLBOX_PL; do
      if ! grep -qE "^#define HAVE_$feature +1" build/config.h; then
        echo "error: mpv was configured without $feature" >&2
        echo "       see build/meson-logs/meson-log.txt (not kept on failure)" >&2
        exit 1
      fi
    done
  '';
  buildPhase = ''
    meson compile -vC build
  '';
  installPhase = ''
    meson install -C build
    mkdir -p $out/share/mpv
    cp configure.log $out/share/mpv/
  '';
}
