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
  includeMoltenvk = os == "ios";
  # Only construct the MoltenVK derivation for iOS (the macOS prebuilt is not
  # wired up yet); Nix would otherwise try to evaluate it for macOS too.
  moltenvk = if includeMoltenvk
    then callPackage ../mk-pkg-moltenvk/default.nix { inherit os arch; }
    else null;
in

# Aggregates the Vulkan libmpv stack into a drop-in directory for the host app:
#   lib/libmpv.dylib   (libplacebo + glslang are statically linked in)
#   include/mpv/*      (mpv public headers)
#   moltenvk/*         (MoltenVK runtime + Vulkan headers)  -- iOS only for now
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
      test -f $out/include/mpv/mpv.h
      test -f $out/include/mpv/render_vk.h
    ''
    + (
      if includeMoltenvk then
        ''
          mkdir -p $out/moltenvk
          cp -a ${moltenvk}/. $out/moltenvk/
          # expose Vulkan headers at the bundle root too, for the host app's SDK path
          mkdir -p $out/include/vulkan
          cp -a ${moltenvk}/include/vulkan/. $out/include/vulkan/ 2>/dev/null || true
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
- MoltenVK (Vulkan loader/ICD for Apple): \`moltenvk/\` on iOS, or drop in
  MoltenVK.framework on macOS.
- System frameworks (added by the host linker):
  - iOS: Metal, CoreVideo, IOSurface, Foundation, AudioToolbox
  - macOS: Metal, CoreVideo, IOSurface, Foundation, CoreAudio

## Runtime
At launch the process must export the Vulkan API. With MoltenVK linked, mpv's
\`vkGetInstanceProcAddr\` resolves against it. No separate vulkan-loader is used.

## media_kit side
The Flutter plugin's \`TextureHW\` must be rewritten to use
\`MPV_RENDER_API_TYPE_VULKAN\` (mpv_kit's private extension) instead of
\`MPV_RENDER_API_TYPE_OPENGL\`. See C-ROUTE-IOS.md.
EOF
    true
  '';
}
