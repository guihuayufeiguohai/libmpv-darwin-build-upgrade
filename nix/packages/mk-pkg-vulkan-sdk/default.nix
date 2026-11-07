{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  glslang = pkgs.callPackage ../mk-pkg-glslang/default.nix {
    inherit os arch;
  };
  vulkanHeaders = pkgs.callPackage ../mk-pkg-vulkan-headers/default.nix {
    inherit os arch;
  };
in

# A single "Vulkan SDK" prefix that satisfies libplacebo's -Dvulkan-sdk option:
#   * lib/            -> libglslang*.a, libSPIRV.a, libMachineIndependent.a, ...
#   * include/glslang -> glslang headers (incl. build_info.h)
#   * include/SPIRV  -> SPIRV headers
#   * include/vulkan -> Vulkan loader/header (used to COMPILE mpv's vulkan code)
#   * share/vulkan/registry/vk.xml -> for -Dvulkan-registry
pkgs.stdenvNoCC.mkDerivation {
  name = "vulkan-sdk-${os}-${arch}";
  pname = "vulkan-sdk";
  version = "1.0";
  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/lib $out/include $out/share/vulkan/registry

    # glslang static libraries
    cp -a ${glslang}/lib/*.a $out/lib/ 2>/dev/null || true
    # glslang + SPIRV headers
    [ -d ${glslang}/include/glslang ] && cp -a ${glslang}/include/glslang $out/include/
    [ -d ${glslang}/include/SPIRV ]   && cp -a ${glslang}/include/SPIRV   $out/include/

    # Vulkan headers + registry
    cp -a ${vulkanHeaders}/include/vulkan $out/include/vulkan
    cp ${vulkanHeaders}/share/vulkan/registry/vk.xml $out/share/vulkan/registry/vk.xml
  '';

  installPhase = ''
    # nothing else; $out is the prefix
    true
  '';
}
