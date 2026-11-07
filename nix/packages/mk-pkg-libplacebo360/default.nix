{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  name = "libplacebo360";
  lock = import ../../../packages.lock.nix;
  packageLock = lock.${name};
  inherit (packageLock) version;

  callPackage = pkgs.lib.callPackageWith {
    inherit pkgs os arch;
  };
  nativeFile = callPackage ../../utils/native-file/default.nix { };
  crossFile = callPackage ../../utils/cross-file/default.nix { };
  # meson's darwin_get_object_archs() shells out to a bare `lipo` from $PATH
  # (it does NOT use the cross-file's [binaries] lipo entry) when it runs
  # find_library() for glslang/SPIRV. Without this, `meson setup` dies with
  # FileNotFoundError: 'lipo'. Same fix mk-pkg-freetype / mk-pkg-mpv use.
  xctoolchainLipo = callPackage ../../utils/xctoolchain/lipo.nix { };
  vulkanSdk = callPackage ../mk-pkg-vulkan-sdk/default.nix { inherit os arch; };

  pname = import ../../utils/name/package.nix name;

  thirdPartySources = {
    fast_float = callPackage ../../utils/fetch-tarball/default.nix {
      name = "libplacebo360-3rdparty-fast_float-source";
      inherit (lock.libplacebo360-3rdparty-fast_float) url sha256;
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
      inherit (lock.vulkan-sdk-headers) url sha256;
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

    # libplacebo 7.360.1 finds glslang with find_library(), which only searches
    # the -Dvulkan-sdk directory when told to. Mirror mpv_kit's seds so the
    # main libglslang and the resource-limits lib are resolved from the SDK's
    # lib/ directory (without these, libplacebo links no glslang frontend and
    # the Vulkan backend fails to load).
    if ! grep -q "find_library('glslang', required: required, static: static)" $src/src/glsl/meson.build; then
      echo "libplacebo360: glslang find_library line not found" >&2
      exit 1
    fi
    sed -i "s|find_library('glslang', required: required, static: static)|find_library('glslang', required: required, static: static, dirs: vulkan_lib_dirs)|" $src/src/glsl/meson.build
    sed -i "s|find_library('glslang-default-resource-limits', required: false)|find_library('glslang-default-resource-limits', required: false, static: true, dirs: [get_option('vulkan-sdk') / 'lib'])|" $src/src/glsl/meson.build

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
    xctoolchainLipo
  ];
  configurePhase = ''
    # libplacebo's Vulkan backend needs the Vulkan headers on the include path
    # (mpv's vulkan code does too). Add them through CFLAGS/CXXFLAGS so we do
    # not clobber the -arch/-isysroot flags the cross file already sets.
    export CFLAGS="-I${vulkanSdk}/include $CFLAGS"
    export CXXFLAGS="-I${vulkanSdk}/include $CXXFLAGS"
    # glslang detection is `cc.has_header('glslang/build_info.h')` with NO
    # `dependencies:` argument, so the SDK include dir has to be on the
    # compiler's own default search path. CPATH is read by clang itself, which
    # makes it independent of whether meson merges env CFLAGS into the cross
    # file's c_args. Missing it only WARNS, and yields a Vulkan backend that
    # cannot compile a single shader at runtime.
    export CPATH="${vulkanSdk}/include:$CPATH"

    # -Dvk-proc-addr=enabled: libplacebo then declares (and uses) the loader's
    # vkGetInstanceProcAddr symbol. The SDK's vulkan.pc deliberately carries an
    # EMPTY Libs, so nothing is linked here; libmpv is a STATIC archive
    # (mpv sets default_library=static), so the symbol stays undefined until the
    # host app links MoltenVK - which it must anyway to create the VkInstance/
    # VkDevice it hands to MPV_RENDER_PARAM_VULKAN_INIT_PARAMS.
    meson setup build $src \
      --native-file ${nativeFile} \
      --cross-file ${crossFile} \
      --prefix=$out \
      -Ddemos=false \
      -Dtests=false \
      -Dbench=false \
      -Dfuzz=false \
      -Dvulkan=enabled \
      -Dvk-proc-addr=enabled \
      -Dvulkan-registry=${vulkanSdk}/share/vulkan/registry/vk.xml \
      -Dopengl=disabled \
      -Dd3d11=disabled \
      -Dglslang=enabled \
      -Dshaderc=disabled \
      -Dlcms=disabled \
      -Ddovi=enabled \
      -Dlibdovi=disabled \
      -Dunwind=disabled \
      -Dxxhash=disabled \
      -Dprefer_static=true \
      -Ddefault_library=static \
      -Dvulkan-sdk=${vulkanSdk}
  '';
  buildPhase = ''
    meson compile -vC build
  '';
  installPhase = ''
    meson install -C build

    # Hard-fail instead of shipping a crippled libplacebo. libplacebo only
    # WARNS when it ends up with Vulkan but no GLSL compiler, and mpv then
    # either drops its Vulkan backend entirely or builds one that cannot
    # compile shaders at runtime. These three flags are exactly what mpv reads
    # back via libplacebo.get_variable().
    echo "--- libplacebo.pc feature variables ---"
    grep '^pl_has_' $out/lib/pkgconfig/libplacebo.pc || true
    for var in pl_has_vulkan pl_has_vk_proc_addr pl_has_glslang; do
      if ! grep -qE "^$var *= *1$" $out/lib/pkgconfig/libplacebo.pc; then
        echo "error: libplacebo was built without $var" >&2
        echo "       see build/meson-logs/meson-log.txt" >&2
        exit 1
      fi
    done

    mkdir -p $out/share/libplacebo
    cp build/meson-logs/meson-log.txt $out/share/libplacebo/ || true
  '';
}
