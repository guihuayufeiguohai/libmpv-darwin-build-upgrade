{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
  variant ? import ../../utils/default/variant.nix,
  flavor ? import ../../utils/default/flavor.nix,
}:

let
  name = "libs";
  version = import ../../utils/version/default.nix { inherit pkgs; };

  archs = import ../../utils/constants/archs.nix;
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
  pname = import ../../utils/name/output.nix name;
in

let
  name = "${pname}-${os}-${arch}-${variant}-${flavor}-${version}";
in

if arch != archs.universal then
  let
    xctoolchainOtool = callPackage ../../utils/xctoolchain/otool.nix { };
    xctoolchainInstallNameTool = callPackage ../../utils/xctoolchain/install-name-tool.nix { };

    mpv = callPackage ../mk-pkg-mpv/default.nix { };
    ffmpeg = callPackage ../mk-pkg-ffmpeg/default.nix { };
    mbedtls = callPackage ../mk-pkg-mbedtls/default.nix { };
    # fftools-ffi is NOT part of the encodersgpl flavor any more: upstream
    # (moffatman/fftools-ffi, commit 9b0d4da0 == its current HEAD) vendors a
    # fork of FFmpeg's fftools from the FFmpeg 6 era and does not compile
    # against FFmpeg 7.0.2 (it fails with deprecated/removed libav* API).
    # The melodink reference build, which also uses FFmpeg 7.0.2, dropped it
    # for the same reason.
    # The package definition (../mk-pkg-fftools-ffi) and its packages.lock.nix
    # entry are kept so it can be re-enabled once ported to FFmpeg 7:
    #   fftoolsFfi = callPackage ../mk-pkg-fftools-ffi/default.nix { };
    libvorbis = callPackage ../mk-pkg-libvorbis/default.nix { };
    libogg = callPackage ../mk-pkg-libogg/default.nix { };
    dav1d = callPackage ../mk-pkg-dav1d/default.nix { };
    libxml2 = callPackage ../mk-pkg-libxml2/default.nix { };
    uchardet = callPackage ../mk-pkg-uchardet/default.nix { };
    libass = callPackage ../mk-pkg-libass/default.nix { };
    # libplacebo became a hard dependency of mpv in 0.37 (vo_gpu-next) and is
    # linked into libmpv, i.e. into Mpv.framework/Mpv. It therefore has to be
    # shipped as Placebo.framework alongside the other frameworks, otherwise
    # the app aborts on launch with:
    #
    #   Library not loaded: @rpath/Placebo.framework/Placebo
    #   Referenced from: .../Runner.app/Frameworks/Mpv.framework/Mpv
    #
    # mk-out-frameworks derives one framework per dylib found under ${DEPS}, so
    # simply adding it here is enough to produce Placebo.framework.
    libplacebo = callPackage ../mk-pkg-libplacebo/default.nix { };
    harfbuzz = callPackage ../mk-pkg-harfbuzz/default.nix { };
    fribidi = callPackage ../mk-pkg-fribidi/default.nix { };
    freetype = callPackage ../mk-pkg-freetype/default.nix { };
    libpng = callPackage ../mk-pkg-libpng/default.nix { };
    libvpx = callPackage ../mk-pkg-libvpx/default.nix { };
    libx264 = callPackage ../mk-pkg-libx264/default.nix { };

    deps =
      [
        mpv
        ffmpeg
        mbedtls
        # Required by libmpv itself (not by the video variant only), so this
        # belongs to the unconditional list: mpv's buildInputs are
        # [ ffmpeg libplacebo libass ] regardless of variant.
        libplacebo
      ]
      ++ pkgs.lib.optionals (flavor == flavors.encodersgpl) [
        libvorbis
        libogg
      ]
      ++ pkgs.lib.optionals (variant == variants.video) [
        dav1d
        libxml2
        uchardet
        libass
        harfbuzz
        fribidi
        freetype
        libpng
      ]
      ++ pkgs.lib.optionals (variant == variants.video && flavor == flavors.encodersgpl) [
        libvpx
        libx264
      ];
  in
  pkgs.stdenvNoCC.mkDerivation {
    inherit name;
    pname = pname;
    inherit version;
    dontUnpack = true;
    enableParallelBuilding = true;
    nativeBuildInputs = [
      xctoolchainInstallNameTool
      xctoolchainOtool
    ];
    buildPhase = ''
      mkdir build

      # Copy dylibs except '*-subset.*.dylib'
      for dep in "${pkgs.lib.concatStringsSep " " deps}"; do
        find $dep/lib \
          -type f -name '*.dylib' \
          ! -name '*-subset.*.dylib' \
          -exec \
          cp {} ./build/ \
          \;
      done

      # Rename dylib libfoo.100.99.88.dylib -> libfoo.dylib
      for file in ./build/lib*.dylib; do
        new_path=$(echo $file | sed -E 's/^(.*\/lib[^.]*).*$/\1.dylib/')
        if [ $file != $new_path ]; then
          mv $file $new_path
        fi
      done

      # Change dylib's id libfoo.dylib -> @rpath/libfoo.dylib
      for file in ./build/lib*.dylib; do
        name=$(basename $file)
        install_name_tool -id @rpath/$name $file
      done

      # Change dylib's dep path /nix/store/**/libfoo.99.dylib -> @rpath/libfoo.99.dylib
      for file in ./build/lib*.dylib; do
        deps=$(otool -L $file | tail -n +3 | sed -n 's|.*\(/nix/store/[^ ]*\).*|\1|p')
        for dep in $deps; do
          name=$(basename $dep)
          install_name_tool -change $dep @rpath/$name $file
        done
      done

      # Change dylib's dep path @rpath/libfoo.99.dylib -> @rpath/libfoo.dylib
      for file in ./build/lib*.dylib; do
        deps=$(otool -L $file | tail -n +3 | sed -n 's|.*\(@rpath/[^ ]*\).*|\1|p')
        for dep in $deps; do
          name=$(echo $dep | sed -n 's|@rpath/\(lib[^.]*\).*|\1.dylib|p')
          install_name_tool -change $dep @rpath/$name $file
        done
      done
    '';
    installPhase = ''
      cp -r build $out
    '';
  }
else
  let
    targets = import ./targets.nix;
    xctoolchainLipo = callPackage ../../utils/xctoolchain/lipo.nix { };

    depArchs = builtins.concatMap (
      target: if target.os == os && target.arch != archs.universal then [ target.arch ] else [ ]
    ) targets;
    deps = builtins.map (
      arch:
      import ./default.nix {
        inherit
          pkgs
          os
          arch
          variant
          flavor
          ;
      }
    ) depArchs;
  in
  pkgs.stdenvNoCC.mkDerivation {
    inherit name;
    pname = pname;
    inherit version;
    dontUnpack = true;
    enableParallelBuilding = true;
    nativeBuildInputs = [
      xctoolchainLipo
    ];
    buildPhase = ''
      mkdir build

      # Concatenate source directories and convert string to array
      deps="${pkgs.lib.concatStringsSep " " deps}"
      read -a deps <<< "$deps"

      # Loop through all .dylib files in the first source directory
      for lib in ''${deps[0]}/*.dylib; do
        lib_name=$(basename $lib)

        # Initialize lipo command
        lipo_cmd="lipo -create"

        # Add each corresponding .dylib file from all source directories
        for dir in ''${deps[@]}; do
          if [ -f $dir/$lib_name ]; then
            lipo_cmd+=" $dir/$lib_name"
          else
            echo "Error: $lib_name not found in $dir" 2> /dev/stderr
            exit 1
          fi
        done

        # Set output to build directory and execute lipo command
        lipo_cmd+=" -output ./build/$lib_name"
        eval "$lipo_cmd"
      done
    '';
    installPhase = ''
      cp -r build $out
    '';
  }
