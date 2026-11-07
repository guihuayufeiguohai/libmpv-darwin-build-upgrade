{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  xcode = pkgs.darwin.xcode;
  # Mirror the SDK selection used by the meson cross files so the C/C++ headers
  # and frameworks come from the same Xcode the rest of the pipeline uses.
  sdk =
    if os == "ios"
    then "${xcode}/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    else "${xcode}/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  archFlag = if arch == "amd64" then "x86_64" else "arm64";
  minVer = if os == "ios" then "12.0" else "10.15";

  cc = "${xcode}/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang";
  cxx = "${xcode}/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++";

  lock = import ../../../packages.lock.nix;
  packageLock = lock.glslang;

  src = pkgs.callPackage ../../utils/fetch-tarball/default.nix {
    name = "glslang-source-${packageLock.version}";
    inherit (packageLock) url sha256;
  };
in

pkgs.stdenvNoCC.mkDerivation {
  name = "glslang-${os}-${arch}-${packageLock.version}";
  pname = "glslang";
  version = packageLock.version;
  inherit src;

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.ninja
  ];

  # glslang is a CMake project; cross-compile it with Xcode's clang against the
  # target SDK. ENABLE_OPT=OFF drops SPIRV-Tools (libplacebo does not need the
  # optimizer and it is the bulk of a shaderc build). No binaries / tests.
  configurePhase = ''
    export CC="${cc}"
    export CXX="${cxx}"
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$out \
      -DCMAKE_OSX_SYSROOT=${sdk} \
      -DCMAKE_OSX_ARCHITECTURES=${archFlag} \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=${minVer} \
      -DCMAKE_C_COMPILER=${cc} \
      -DCMAKE_CXX_COMPILER=${cxx} \
      -DBUILD_SHARED_LIBS=OFF \
      -DENABLE_OPT=OFF \
      -DGLSLANG_TESTS=OFF \
      -DENABLE_GLSLANG_BINARIES=OFF \
      -DENABLE_HLSL=OFF \
      -DGLSLANG_ENABLE_INSTALL=ON \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  '';

  buildPhase = ''
    cmake --build build
  '';

  installPhase = ''
    cmake --install build --strip
  '';
}
