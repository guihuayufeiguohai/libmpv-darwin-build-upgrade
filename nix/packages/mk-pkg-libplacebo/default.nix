{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  name = "libplacebo";
  lock = import ../../../packages.lock.nix;
  packageLock = lock.${name};
  inherit (packageLock) version;

  callPackage = pkgs.lib.callPackageWith {
    inherit
      pkgs
      os
      arch
      ;
  };
  nativeFile = callPackage ../../utils/native-file/default.nix { };
  crossFile = callPackage ../../utils/cross-file/default.nix { };

  pname = import ../../utils/name/package.nix name;

  # GitHub's auto-generated archives do not contain git submodules, so the
  # vendored 3rdparty sources have to be fetched separately and unpacked into
  # ./3rdparty under the exact names libplacebo's meson expects.
  thirdPartySources = {
    fast_float = callPackage ../../utils/fetch-tarball/default.nix {
      name = "libplacebo-3rdparty-fast_float-source";
      inherit (lock.libplacebo-3rdparty-fast_float) url sha256;
    };
    glad = callPackage ../../utils/fetch-tarball/default.nix {
      name = "libplacebo-3rdparty-glad-source";
      inherit (lock.libplacebo-3rdparty-glad) url sha256;
    };
    jinja = callPackage ../../utils/fetch-tarball/default.nix {
      name = "libplacebo-3rdparty-jinja-source";
      inherit (lock.libplacebo-3rdparty-jinja) url sha256;
    };
    markupsafe = callPackage ../../utils/fetch-tarball/default.nix {
      name = "libplacebo-3rdparty-markupsafe-source";
      inherit (lock.libplacebo-3rdparty-markupsafe) url sha256;
    };
    vulkan-headers = callPackage ../../utils/fetch-tarball/default.nix {
      name = "libplacebo-3rdparty-Vulkan-Headers-source";
      inherit (lock.libplacebo-3rdparty-vulkan-headers) url sha256;
    };
  };

  src = callPackage ../../utils/fetch-tarball/default.nix {
    name = "${pname}-source-${version}";
    inherit (packageLock) url sha256;
  };
  patchedSource = pkgs.runCommand "${pname}-patched-source-${version}" { } ''
    cp -r ${src} src
    export src=$PWD/src
    chmod -R 777 $src

    rm -rf $src/3rdparty
    mkdir -p $src/3rdparty

    cp -r ${thirdPartySources.fast_float} $src/3rdparty/fast_float
    cp -r ${thirdPartySources.glad} $src/3rdparty/glad
    cp -r ${thirdPartySources.jinja} $src/3rdparty/jinja
    cp -r ${thirdPartySources.markupsafe} $src/3rdparty/markupsafe
    cp -r ${thirdPartySources.vulkan-headers} $src/3rdparty/Vulkan-Headers

    chmod -R 777 $src/3rdparty

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
  nativeBuildInputs = [
    pkgs.meson
    pkgs.ninja
    pkgs.pkg-config
    pkgs.python3
  ];
  configurePhase = ''
    # mpv's gpu-next libmpv render backend needs libplacebo built with
    # PL_HAVE_OPENGL. The 'auto' default already enables it (glad is vendored
    # above and the OpenGL sources need no system GL headers), but pin it
    # explicitly so an upstream default change cannot silently turn gpu-next
    # -- and with it Dolby Vision Profile 5 -- back off.
    meson setup build $src \
      --native-file ${nativeFile} \
      --cross-file ${crossFile} \
      --prefix=$out \
      -Ddemos=false \
      -Dtests=false \
      -Dopengl=enabled
  '';
  buildPhase = ''
    meson compile -vC build
  '';
  installPhase = ''
    meson install -C build

    # keep the resolvable view of libplacebo next to the library so that the
    # resulting build stays debuggable
    mkdir -p $out/share/libplacebo
    cp build/meson-logs/meson-log.txt $out/share/libplacebo/ || true
  '';
}
