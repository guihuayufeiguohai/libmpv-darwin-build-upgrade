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

    # libplacebo 7.349.0 enables GPU timer queries on *any* GLES 3.0 context:
    #
    #   p->has_queries = gl_test_ext(gpu, "GL_ARB_timer_query", 30, 30);
    #
    # The 30/30 thresholds mean GLES 3.0 is treated as equivalent to desktop
    # GL 3.0, but GL_ARB_timer_query / GL_TIME_ELAPSED does not exist on iOS
    # GLES (it would need GL_EXT_disjoint_timer_query + GL_TIME_ELAPSED_EXT).
    # gl_timer_begin() then calls glBeginQuery(GL_TIME_ELAPSED, ...), and the
    # Apple OpenGLES driver aborts the process with
    #   "failed assertion ... in beginQuery. unsupported query type" (SIGABRT)
    # as soon as the first gpu-next frame is dispatched.
    #
    # Timer queries only feed shader performance statistics, never rendering,
    # so disable them. pl_timer_create() then returns NULL, and libplacebo's
    # pl_timer_destroy() / pl_timer_query() / gl_timer_begin() / gl_timer_end()
    # all return early on a NULL timer.
    if ! grep -q 'p->has_queries = gl_test_ext(gpu, "GL_ARB_timer_query", 30, 30);' $src/src/opengl/gpu.c; then
      echo "libplacebo: timer-query line not found, refusing to build unpatched" >&2
      exit 1
    fi
    sed -i 's|p->has_queries = gl_test_ext(gpu, "GL_ARB_timer_query", 30, 30);|p->has_queries = false; // Darwin GLES: GL_TIME_ELAPSED is unsupported|' $src/src/opengl/gpu.c
    if ! grep -q 'p->has_queries = false;' $src/src/opengl/gpu.c; then
      echo "libplacebo: failed to disable timer queries" >&2
      exit 1
    fi

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
