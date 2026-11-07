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
  lock = import ../../../packages.lock.nix;
  # Must match the bundled Vulkan-Headers exactly. Two independent consumers
  # compare this version number:
  #   mpv        -> dependency('vulkan', version: '>= 1.3.238')
  #   libplacebo -> pl_has_vulkan in libplacebo.pc, gated on VK_VERSION_1_4
  vulkanHeadersVersion = lock.vulkan-sdk-headers.version;
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

    # vulkan.pc: both consumers resolve Vulkan through pkg-config.
    #   mpv:        vulkan = dependency('vulkan', version: '>= 1.3.238', ...)
    #               cc.has_header_symbol('vulkan/vulkan_core.h', 'VK_VERSION_1_3',
    #                                    dependencies: vulkan)
    #   libplacebo: vulkan_loader = dependency('vulkan', required: false)
    #               cc.has_header_symbol('vulkan/vulkan_core.h', 'VK_VERSION_1_4',
    #                                    dependencies: vulkan_headers)
    # Headers only: on Apple the loader/ICD is MoltenVK, which the host app
    # links; mpv/libplacebo reach the API through vkGetInstanceProcAddr at
    # runtime (libplacebo is built with -Dvk-proc-addr=enabled), so an empty
    # Libs is deliberate and keeps libmpv free of a hard libvulkan dependency.
    mkdir -p $out/lib/pkgconfig
    printf '%s\n' \
      "includedir=$out/include" \
      "Name: vulkan" \
      "Description: Vulkan headers (loader/ICD provided by MoltenVK in the host app)" \
      "Version: ${vulkanHeadersVersion}" \
      "Cflags: -I$out/include" \
      "Libs:" \
      > $out/lib/pkgconfig/vulkan.pc
  '';

  installPhase = ''
    # nothing else; $out is the prefix
    true
  '';
}
