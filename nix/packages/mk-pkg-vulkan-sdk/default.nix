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
  # Vulkan implementation for Apple platforms. Linking it here (via vulkan.pc
  # below) is what makes libmpv carry a real vkGetInstanceProcAddr instead of
  # leaving it as an undefined symbol resolved by -undefined dynamic_lookup,
  # which is unreliable on iOS. moltenvk does not depend on this package, so
  # there is no cycle.
  moltenvk = pkgs.callPackage ../mk-pkg-moltenvk/default.nix {
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
#   * include/vulkan -> Vulkan headers (used to COMPILE mpv's vulkan code)
#   * include/vk_video -> pulled in unconditionally by vulkan_core.h (1.4+)
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
    # vk_video/ is NOT optional from Vulkan-Headers 1.4 on: vulkan_core.h
    # includes "vk_video/vulkan_video_codec_*.h" unconditionally (Vulkan Video
    # is core since 1.3), so without this every consumer dies with
    #   vulkan_core.h:9805:10: fatal error:
    #   'vk_video/vulkan_video_codec_h264std.h' file not found
    if [ -d ${vulkanHeaders}/include/vk_video ]; then
      cp -a ${vulkanHeaders}/include/vk_video $out/include/vk_video
    fi
    test -f $out/include/vulkan/vulkan_core.h
    test -f $out/include/vk_video/vulkan_video_codec_h264std.h
    cp ${vulkanHeaders}/share/vulkan/registry/vk.xml $out/share/vulkan/registry/vk.xml

    # vulkan.pc: both consumers resolve Vulkan through pkg-config.
    #   mpv:        vulkan = dependency('vulkan', version: '>= 1.3.238', ...)
    #               cc.has_header_symbol('vulkan/vulkan_core.h', 'VK_VERSION_1_3',
    #                                    dependencies: vulkan)
    #   libplacebo: vulkan_loader = dependency('vulkan', required: false)
    #               cc.has_header_symbol('vulkan/vulkan_core.h', 'VK_VERSION_1_4',
    #                                    dependencies: vulkan_headers)
    # Libs carries MoltenVK: on Apple it is the only Vulkan implementation, and
    # libmpv must resolve vkGetInstanceProcAddr itself. Before this, Libs was
    # empty and the symbol stayed undefined, relying on
    # -undefined dynamic_lookup to be satisfied by whatever the host process
    # happened to export -- workable on macOS, unreliable on iOS.
    # libplacebo is built with -Dvk-proc-addr=enabled so it only *declares*
    # vkGetInstanceProcAddr; the static link happens once, when libmpv is
    # linked, so MoltenVK is not duplicated into libplacebo.a.
    mkdir -p $out/lib/pkgconfig
    printf '%s\n' \
      "includedir=$out/include" \
      "Name: vulkan" \
      "Description: Vulkan headers + MoltenVK static library" \
      "Version: ${vulkanHeadersVersion}" \
      "Cflags: -I$out/include" \
      "Libs: -L${moltenvk}/lib -lMoltenVK" \
      > $out/lib/pkgconfig/vulkan.pc
  '';

  installPhase = ''
    # nothing else; $out is the prefix
    true
  '';
}
