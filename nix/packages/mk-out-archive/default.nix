{
  pkgs ? import ../../utils/default/pkgs.nix,
  format ? import ../../utils/default/format.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
  variant ? import ../../utils/default/variant.nix,
  flavor ? import ../../utils/default/flavor.nix,
}:

let
  name = "archive";
  version = import ../../utils/version/default.nix { inherit pkgs; };

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
  formats = import ../../utils/constants/formats.nix;
  archiveBaseName = "libmpv-${format}_${version}_${os}-${arch}-${variant}-${flavor}";
  src =
    if format == formats.libs then
      callPackage ../mk-out-libs/default.nix { }
    else if format == formats.xcframeworks then
      callPackage ../mk-out-xcframeworks/default.nix { }
    else
      abort "Format ${format} is not supported";
in

pkgs.stdenvNoCC.mkDerivation {
  name = "${pname}-${format}-${os}-${arch}-${variant}-${flavor}-${version}";
  inherit pname;
  inherit version;
  dontUnpack = true;
  enableParallelBuilding = true;
  nativeBuildInputs = pkgs.lib.optionals (format == formats.xcframeworks) [
    pkgs.zip
  ];
  inherit src;
  buildPhase = ''
    build=$PWD/build
    mkdir -p $build

    cp --no-preserve=mode -r $src ${archiveBaseName}
    tar -czvf $build/${archiveBaseName}.tar.gz ${archiveBaseName}
  ''
  + pkgs.lib.optionalString (format == formats.xcframeworks) ''
    (
      cd ${archiveBaseName}
      for XCFRAMEWORK in *.xcframework; do
        FRAMEWORK_NAME=$(basename $XCFRAMEWORK .xcframework)
        zip -Xyr $build/${archiveBaseName}_$FRAMEWORK_NAME.zip $XCFRAMEWORK
      done
    )
  '';
  installPhase = ''
    cp -r $build $out
  '';
}
