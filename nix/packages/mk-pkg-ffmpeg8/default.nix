{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
  variant ? import ../../utils/default/variant.nix,
  flavor ? import ../../utils/default/flavor.nix,
}:

let
  name = "ffmpeg";
  # Isolated FFmpeg 8.1.3 for the Vulkan route. mk-pkg-ffmpeg (7.0.2) is left
  # untouched: it is shared by mk-pkg-mpv (OpenGL), mk-out-libs,
  # mk-pkg-fftools-ffi and mk-pkg-mpv-vulkan, and upgrading it in place would
  # break the already-working GL build.
  #
  # Why 8.1.3: libplacebo's pl_map_avdovi_metadata() only reads the L1
  # per-frame dynamic luminance (max_pq_y / avg_pq_y) when
  #   LIBAVUTIL_VERSION_INT >= AV_VERSION_INT(59, 12, 100)
  # FFmpeg 7.0.2 ships libavutil 59.8.100, so that block is compiled out and
  # Dolby Vision P8 tone mapping loses its per-frame metadata. 8.1.3 ships
  # libavutil 60.x and enables it.
  packageLock = (import ../../../packages.lock.nix).ffmpeg8;
  inherit (packageLock) version;

  flavors = import ../../utils/constants/flavors.nix;
  variants = import ../../utils/constants/variants.nix;
  callPackage = pkgs.lib.callPackageWith {
    inherit
      pkgs
      os
      arch
      variant
      flavor
      ;
  };
  nativeFile = callPackage ../../utils/native-file/default.nix { };
  crossFile = callPackage ../../utils/cross-file/default.nix { };
  mbedtls = callPackage ../mk-pkg-mbedtls/default.nix { };
  dav1d = callPackage ../mk-pkg-dav1d/default.nix { };
  libxml2 = callPackage ../mk-pkg-libxml2/default.nix { };
  libvorbis = callPackage ../mk-pkg-libvorbis/default.nix { };
  libvpx = callPackage ../mk-pkg-libvpx/default.nix { };
  libx264 = callPackage ../mk-pkg-libx264/default.nix { };

  pname = import ../../utils/name/package.nix name;
  src = callPackage ../../utils/fetch-tarball/default.nix {
    name = "${pname}-source-${version}";
    inherit (packageLock) url sha256 mirrors;
  };
  # Deliberately NO patches -- clean upstream FFmpeg 8.1.3, like mpv_kit's
  # ffmpeg.sh. All three patches from the 7.0.2 package are wrong here:
  #
  #  * ffmpeg-fix-vp9-hwaccel.patch adds an
  #      extern const FFCodec ff_vp9_videotoolbox_decoder;
  #    declaration that upstream FFmpeg 8 already provides -> duplicate.
  #
  #  * ffmpeg-fix-ios-hdr-texture.patch forces 10-bit iOS video to
  #      AV_PIX_FMT_BGRA (8-bit) because "iOS doesn't support 10 bit textures
  #    in GLES". The Vulkan/Metal route has no such limitation, so keeping it
  #    would silently destroy HDR / Dolby Vision precision.
  #
  #  * ffmpeg-fix-dash-base-url-escape.patch (and the already-disabled
  #    hls-mp4-seek one) target FFmpeg 6/7 internals. Re-evaluate only if a
  #    concrete DASH/HLS regression shows up.
  patchedSource = pkgs.runCommand "${pname}-patched-source-${version}" { } ''
    cp -r ${src} src
    export src=$PWD/src
    chmod -R 777 $src

    cp ${./meson.build} $src/meson.build
    cp ${./meson.options} $src/meson.options

    cp -r $src $out
  '';
in

pkgs.stdenvNoCC.mkDerivation {
  name = "${pname}-${os}-${arch}-${variant}-${flavor}-${version}";
  pname = pname;
  inherit version;
  src = patchedSource;
  dontUnpack = true;
  enableParallelBuilding = true;
  nativeBuildInputs = [
    pkgs.meson
    pkgs.ninja
    pkgs.pkg-config
  ];
  buildInputs =
    [ mbedtls ]
    ++ pkgs.lib.optionals (flavor == flavors.encodersgpl) [
      libvorbis
    ]
    ++ pkgs.lib.optionals (variant == variants.video) [
      dav1d
      libxml2
    ]
    ++ pkgs.lib.optionals (variant == variants.video && flavor == flavors.encodersgpl) [
      libvpx
      libx264
    ];
  configurePhase = ''
    meson setup build $src \
      --native-file ${nativeFile} \
      --cross-file ${crossFile} \
      --prefix=$out \
      -Dvariant=${variant} \
      -Dflavor=${flavor} |
      tee configure.log
  '';
  buildPhase = ''
    meson compile -vC build $(basename $src)
  '';
  installPhase = ''
    # manual install to preserve symlinks (meson install -C build)
    cp -r build/dist$out $out

    # copy configure.log
    cp configure.log $out/share/ffmpeg/
  '';
}
