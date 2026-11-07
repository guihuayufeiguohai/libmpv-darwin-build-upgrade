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
  xctoolchainLipo = callPackage ../../utils/xctoolchain/lipo.nix { };
  vulkanSdk = callPackage ../mk-pkg-vulkan-sdk/default.nix { inherit os arch; };

  # Only used by the on-failure diagnostics below: a direct probe of the exact
  # header check mpv's meson performs, so a failed run reports why.
  xcode = pkgs.darwin.xcode;
  sdk =
    if os == oses.ios
    then "${xcode}/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    else "${xcode}/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  xcClang = "${xcode}/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang";
  archFlag = if arch == "amd64" then "x86_64" else "arm64";

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

    cd -

    cp -r $src $out
  '';
in

pkgs.stdenvNoCC.mkDerivation {
  name = "${pname}-${os}-${arch}-${version}";
  pname = pname;
  inherit version;
  src = patchedSource;
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
      --cross-file ${crossFile} \
      --prefix=$out \
      "''${OPTIONS[@]}" |
      tee configure.log || {
        echo "=== meson setup FAILED; diagnostics ===" >&2
        echo "--- pkg-config vulkan ---" >&2
        pkg-config --modversion vulkan >&2 || true
        pkg-config --cflags vulkan >&2 || true
        echo "--- SDK headers ---" >&2
        ls -l ${vulkanSdk}/include/vulkan/vulkan_core.h >&2 || true
        echo "--- env ---" >&2
        echo "CPATH=$CPATH" >&2
        echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH" >&2
        echo "--- configure.log tail ---" >&2
        tail -n 40 configure.log >&2 || true
        echo "--- direct header probe with pkg-config cflags ---" >&2
        printf '%s\n' '#include <vulkan/vulkan_core.h>' \
          '#ifndef VK_VERSION_1_3' '#error VK_VERSION_1_3 undefined' '#endif' \
          'int main(void){return 0;}' > probe.c
        ${xcClang} -arch ${archFlag} -isysroot ${sdk} \
          $(pkg-config --cflags vulkan) -c probe.c -o probe.o >&2 2>&1 \
          && echo "probe(pcflags): OK" >&2 \
          || echo "probe(pcflags): FAILED" >&2
        ${xcClang} -arch ${archFlag} -isysroot ${sdk} \
          -I${vulkanSdk}/include -c probe.c -o probe.o >&2 2>&1 \
          && echo "probe(explicit -I): OK" >&2 \
          || echo "probe(explicit -I): FAILED" >&2
        echo "--- meson-log.txt tail ---" >&2
        tail -n 120 build/meson-logs/meson-log.txt >&2 || true
        exit 1
      }

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
