{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  name = "libpng";
  packageLock = (import ../../../packages.lock.nix).${name};
  packagePatchLock = (import ../../../packages.lock.nix).libpngPatch;
  inherit (packageLock) version;

  callPackage = pkgs.lib.callPackageWith { inherit pkgs os arch; };
  nativeFile = callPackage ../../utils/native-file/default.nix { };
  crossFile = callPackage ../../utils/cross-file/default.nix { };

  pname = import ../../utils/name/package.nix name;
  src = callPackage ../../utils/fetch-tarball/default.nix {
    name = "${pname}-source-${version}";
    inherit (packageLock) url sha256;
  };
  libpngPatch = builtins.fetchurl {
    inherit (packagePatchLock) url sha256;
  };
  patchedSource =
    pkgs.runCommand "${pname}-patched-source-${version}"
      {
        nativeBuildInputs = [
          pkgs.unzip
          pkgs.rsync
        ];
      }
      ''
        cp -r ${src} src
        export src=$PWD/src
        chmod -R 777 $src

        # extract and patch libpng dependency
        unzip ${libpngPatch} -d libpng-patch
        rsync -a libpng-patch/libpng-*/ $src/

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
