{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  xcode = pkgs.darwin.xcode;
  sdk =
    if os == "ios"
    then "${xcode}/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    else "${xcode}/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  archFlag = if arch == "amd64" then "x86_64" else "arm64";

  cc = "${xcode}/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang";
  cxx = "${xcode}/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++";

  lock = import ../../../packages.lock.nix;
  # 1.4.363.0: libplacebo 7.360.1 requires VK_VERSION_1_4 in vulkan_core.h, so
  # the Vulkan route cannot use the 1.3.243 headers the OpenGL build pins.
  packageLock = lock.vulkan-sdk-headers;

  src = pkgs.callPackage ../../utils/fetch-tarball/default.nix {
    name = "vulkan-headers-source-${packageLock.version}";
    inherit (packageLock) url sha256;
  };
in

pkgs.stdenvNoCC.mkDerivation {
  name = "vulkan-headers-${os}-${arch}-${packageLock.version}";
  pname = "vulkan-headers";
  version = packageLock.version;
  inherit src;

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.ninja
  ];

  configurePhase = ''
    export CC="${cc}"
    export CXX="${cxx}"
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$out \
      -DCMAKE_OSX_SYSROOT=${sdk} \
      -DCMAKE_OSX_ARCHITECTURES=${archFlag} \
      -DCMAKE_C_COMPILER=${cc} \
      -DCMAKE_CXX_COMPILER=${cxx} \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  '';

  buildPhase = ''
    cmake --build build
  '';

  installPhase = ''
    cmake --install build
    # libplacebo's -Dvulkan-registry wants the registry XML; the Vulkan-Headers
    # CMake install does not ship it, so copy it from the source tree.
    mkdir -p $out/share/vulkan/registry
    cp registry/vk.xml $out/share/vulkan/registry/vk.xml
  '';
}
