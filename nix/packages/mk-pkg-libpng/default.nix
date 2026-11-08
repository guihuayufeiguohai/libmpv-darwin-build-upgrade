{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  name = "libpng";
  packageLock = (import ../../../packages.lock.nix).${name};
  inherit (packageLock) version;

  callPackage = pkgs.lib.callPackageWith { inherit pkgs os arch; };
  nativeFile = callPackage ../../utils/native-file/default.nix { };
  crossFile = callPackage ../../utils/cross-file/default.nix { };

  pname = import ../../utils/name/package.nix name;
  src = callPackage ../../utils/fetch-tarball/default.nix {
    name = "${pname}-source-${version}";
    inherit (packageLock) url sha256;
  };
  # The upstream libpng 1.6.40 tarball has no meson.build. meson's wrapdb
  # used to provide it through
  #   https://wrapdb.mesonbuild.com/v2/libpng_1.6.40-1/get_patch
  # downloaded with builtins.fetchurl during Nix *evaluation* -- so a 504
  # from wrapdb killed the whole build before a single file was compiled.
  # wrapdb's tag libpng_1.6.40-1 contains exactly ONE file in
  # subprojects/packagefiles/libpng: meson.build (3761 bytes), and that tag's
  # libpng.wrap declares source_hash == packages.lock.nix's libpng sha256.
  # Vendoring this single file is byte-equivalent and removes the fragile
  # external dependency from evaluation altogether.
  patchedSource =
    pkgs.runCommand "${pname}-patched-source-${version}" { } ''
      cp -r ${src} src
      export src=$PWD/src
      chmod -R 777 $src

      cp ${./libpng-1.6.40-meson.build} $src/meson.build

      # libpng 1.6.40 does `#include <fp.h>` on Apple targets, but fp.h was
      # removed from modern macOS SDKs (Xcode 11+), so clang fails with
      # "fatal error: 'fp.h' file not found". The surrounding logic is
      #   #if !defined(__MATH_H__) ... #include <fp.h> #else #include <math.h>
      # i.e. fp.h *replaces* math.h on old Apple compilers. Simply dropping
      # the include would take the (now empty) #if branch and skip math.h,
      # leaving modf/floor/pow undeclared. So replace it with <math.h>.
      # Grep-verify so a future source bump fails loudly.
      if grep -q 'include <fp.h>' $src/pngpriv.h; then
        sed -i -E 's@^[[:space:]]*#[[:space:]]*include[[:space:]]*<fp\.h>.*$@#      include <math.h>@' $src/pngpriv.h
      fi
      if grep -q 'include <fp.h>' $src/pngpriv.h; then
        echo "libpng: failed to strip <fp.h> include from pngpriv.h" >&2
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
  ];
  configurePhase = ''
    meson setup build $src \
      --native-file ${nativeFile} \
      --cross-file ${crossFile} \
      --prefix=$out
  '';
  buildPhase = ''
    meson compile -vC build
  '';
  installPhase = ''
    meson install -C build
  '';
}
