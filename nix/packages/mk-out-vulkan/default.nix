{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  oses = import ../../utils/constants/oses.nix;
  callPackage = pkgs.lib.callPackageWith {
    inherit pkgs os arch;
  };
  mpvVulkan = callPackage ../mk-pkg-mpv-vulkan/default.nix { inherit os arch; };
  # MoltenVK is the only Vulkan implementation on Apple platforms, so both
  # bundles carry it: iOS gets static + dynamic, macOS gets the universal
  # macos-arm64_x86_64 static library (MoltenVK-macos.tar has no dynamic
  # framework).
  includeMoltenvk = os == "ios" || os == "macos";
  moltenvk = if includeMoltenvk
    then callPackage ../mk-pkg-moltenvk/default.nix { inherit os arch; }
    else null;
  # Host-facing Vulkan headers must match the ones libmpv/libplacebo were
  # COMPILED against. MoltenVK's tarball bundles VK_HEADER_VERSION 357
  # (Vulkan 1.3.357), while this build compiles against vulkan-sdk-headers
  # 1.4.363.0. Shipping the older headers would make the host app see
  # different struct definitions than the binary was built with, so the
  # bundle takes them from the SDK prefix instead.
  vulkanSdk = callPackage ../mk-pkg-vulkan-sdk/default.nix { inherit os arch; };
in

# Aggregates the Vulkan libmpv stack into a drop-in directory for the host app:
#   lib/libmpv.dylib   (libplacebo + glslang are statically linked in)
#   include/mpv/*      (mpv public headers)
#   moltenvk/*         (MoltenVK runtime + Vulkan headers)  -- iOS and macOS
#   README.md          (integration steps for media_kit's new TextureHW)
pkgs.stdenvNoCC.mkDerivation {
  name = "vulkan-bundle-${os}-${arch}";
  pname = "vulkan-bundle";
  version = "stage2";
  dontUnpack = true;

  buildInputs = [ mpvVulkan ] ++ pkgs.lib.optional includeMoltenvk moltenvk;

  # NOTE: Nix interpolates every `${...}` in this string *before* bash runs it,
  # so `${moltenvk}` (null for macOS) must be gated at the Nix level. Doing it
  # with a bash `if` still forces Nix to coerce the null -> "cannot coerce null
  # to a string". Hence the string concatenation below.
  buildPhase =
    ''
      mkdir -p $out/lib $out/include
      # libmpv (self-contained: libplacebo + glslang statically linked)
      #
      # Copy the whole lib dir rather than the two names we happen to expect:
      # meson installs the real object as libmpv.2.dylib plus a relative
      # symlink libmpv.dylib -> libmpv.2.dylib, and `cp -a` of just the symlink
      # would leave a dangling link in $out (and silently drop the binary).
      cp -a ${mpvVulkan}/lib/. $out/lib/
      [ -d ${mpvVulkan}/include ] && cp -a ${mpvVulkan}/include/mpv $out/include/ 2>/dev/null || true

      # mpv 0.41 builds libmpv as a versioned dylib (libmpv.2.dylib) by default;
      # libmpv.a only appears if default_library is switched to static. Accept
      # either, but never an empty lib/ - the bundle would look fine and be
      # unusable.
      if [ ! -f $out/lib/libmpv.a ] \
         && ! ls $out/lib/libmpv*.dylib >/dev/null 2>&1; then
        echo "error: mpv install produced no libmpv (neither .a nor .dylib)" >&2
        echo "       contents of ${mpvVulkan}/lib:" >&2
        ls -l ${mpvVulkan}/lib >&2 || true
        exit 1
      fi
      # media_kit compiles against these; a missing header dir is a broken SDK.
      # NOTE: mpv 0.41 has no umbrella include/mpv/mpv.h (only client.h,
      # render.h, render_gl.h, render_vk.h, stream_cb.h), so assert those.
      test -f $out/include/mpv/client.h
      test -f $out/include/mpv/render_vk.h
    ''
    + (
      if includeMoltenvk then
        ''
          mkdir -p $out/moltenvk
          cp -a ${moltenvk}/. $out/moltenvk/
          # Host-facing Vulkan headers, taken from the SDK prefix so they are
          # exactly the 1.4.363.0 ones libmpv was compiled against (moltenvk's
          # own copy is 1.3.357). vk_video/ is required because 1.4 headers
          # include it unconditionally.
          mkdir -p $out/include/vulkan $out/include/vk_video
          cp -a ${vulkanSdk}/include/vulkan/. $out/include/vulkan/
          cp -a ${vulkanSdk}/include/vk_video/. $out/include/vk_video/
          test -f $out/include/vulkan/vulkan_core.h
          test -f $out/include/vk_video/vulkan_video_codec_h264std.h
          grep -q 'define VK_HEADER_VERSION 363' $out/include/vulkan/vulkan_core.h
        ''
      else
        ''
          cat > $out/README.moltenvk.macos.md <<'EOF'
          This macOS bundle does NOT yet include MoltenVK (only the iOS MoltenVK
          prebuilt is wired up). Download MoltenVK-macos.tar from
          https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.2 and drop
          MoltenVK/dynamic/MoltenVK.xcframework + MoltenVK/include into this
          directory before embedding in your app.
          EOF
        ''
    );

  installPhase = ''
    cat > $out/README.md <<EOF
# Vulkan libmpv bundle (${os}-${arch})

This is the C-route Vulkan build of libmpv for media_kit. libplacebo (7.360.1)
and glslang (16.6.0) are statically linked into \`lib/libmpv.dylib\`.

## What you need to link in your app
- \`lib/libmpv.dylib\`
- MoltenVK (the Vulkan implementation on Apple): \`moltenvk/\` in this bundle.
  iOS ships \`lib/libMoltenVK.a\` plus \`MoltenVK.xcframework\`; macOS ships the
  universal \`macos-arm64_x86_64\` static library.
- System frameworks (added by the host linker):
  - iOS: Metal, CoreVideo, IOSurface, Foundation, AudioToolbox
  - macOS: Metal, CoreVideo, IOSurface, Foundation, CoreAudio

## Runtime
libmpv already links MoltenVK statically, so \`vkGetInstanceProcAddr\` is
resolved inside \`libmpv.dylib\`; the app does not have to export it. No
separate vulkan-loader is used.

## media_kit side
The Flutter plugin's \`TextureHW\` must be rewritten to use
\`MPV_RENDER_API_TYPE_VULKAN\` (mpv_kit's private extension) instead of
\`MPV_RENDER_API_TYPE_OPENGL\`. See C-ROUTE-IOS.md.
EOF
    true
  '';
}
