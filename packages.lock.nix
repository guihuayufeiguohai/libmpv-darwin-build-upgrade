{
  # MoltenVK 1.4.2 iOS runtime (prebuilt). Hash verified locally against the
  # official GitHub release asset MoltenVK-ios.tar (34,535,424 bytes).
  # Only the ios-arm64 slice is present: there is NO simulator slice in this
  # archive, so Vulkan can only be enabled for real iOS arm64 devices.
  moltenvk = {
    version = "1.4.2";
    url = "https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-ios.tar";
    sha256 = "b5d947b1660e6e9fed40b9cd2387e160aaab9e80b775c0cef7e14059405178c1";
  };
  # glslang is required by libplacebo's Vulkan backend to compile generated
  # GLSL into SPIR-V at runtime. Pinned for stage 2; hash from mpv_kit's
  # native/build/deps.sh (same upstream tarball).
  glslang = {
    version = "16.6.0";
    url = "https://github.com/KhronosGroup/glslang/archive/refs/tags/16.6.0.tar.gz";
    sha256 = "9c09b901149c729df745057dafa815278aaa101b84d2b6e14f16a42de52f97f2";
  };
  # libplacebo 7.360.1: the Vulkan route pins this exact version because
  # mpv_kit's Vulkan render-backend patches and glslang meson seds target it
  # (7.349.0's glslang detection is missing find_library('glslang') and links
  # nothing -> undefined symbols). The existing GL build keeps 7.349.0.
  libplacebo360 = {
    version = "7.360.1";
    url = "https://code.videolan.org/videolan/libplacebo/-/archive/v7.360.1/libplacebo-v7.360.1.tar.gz";
    sha256 = "14c0a99f4b01557ec9826ce6b1d52f6de21be274ba03fd5aab7307f18766dc39";
  };
  # libplacebo 7.360.1 needs fast_float >= 8.x (7.349.0 used 5.2.0).
  libplacebo360-3rdparty-fast_float = {
    version = "8.3.2";
    url = "https://github.com/fastfloat/fast_float/archive/refs/tags/v8.3.2.tar.gz";
    sha256 = "71bb9e865b888df01351558db5a39586d13ea97ada162156b3a07784d8c1b26b";
  };
  dav1d = {
    version = "1.2.1";
    url = "https://code.videolan.org/videolan/dav1d/-/archive/1.2.1/dav1d-1.2.1.tar.bz2";
    sha256 = "a4003623cdc0109dec3aac8435520aa3fb12c4d69454fa227f2658cdb6dab5fa";
  };
  ffmpeg = {
    version = "7.0.2";
    url = "https://ffmpeg.org/releases/ffmpeg-7.0.2.tar.xz";
    # Mirrors tried (in order) if ffmpeg.org is unreachable/flaky in CI.
    # Each serves the identical tarball, so the same sha256 applies.
    mirrors = [
      "https://www.mirrorservice.org/sites/ffmpeg.org/releases/ffmpeg-7.0.2.tar.xz"
      "https://mirror.clarkson.edu/ffmpeg/releases/ffmpeg-7.0.2.tar.xz"
    ];
    sha256 = "8646515b638a3ad303e23af6a3587734447cb8fc0a0c064ecdb8e95c4fd8b389";
  };
  fftools-ffi = {
    version = "9b0d4da0";
    url = "https://github.com/moffatman/fftools-ffi/archive/9b0d4da026d9c830702ec043c1f1f98d407025af.tar.gz";
    sha256 = "mgf3ddt3yjmYBd2D0WeEnhgxKNjrEbjYnDx2t4YCfU8=";
  };
  freetype = {
    version = "2.13.2";
    url = "https://downloads.sourceforge.net/project/freetype/freetype2/2.13.2/freetype-2.13.2.tar.xz";
    sha256 = "12991c4e55c506dd7f9b765933e62fd2be2e06d421505d7950a132e4f1bb484d";
  };
  fribidi = {
    version = "1.0.13";
    url = "https://github.com/fribidi/fribidi/releases/download/v1.0.13/fribidi-1.0.13.tar.xz";
    sha256 = "7fa16c80c81bd622f7b198d31356da139cc318a63fc7761217af4130903f54a2";
  };
  harfbuzz = {
    version = "8.1.1";
    url = "https://github.com/harfbuzz/harfbuzz/archive/8.1.1.tar.gz";
    sha256 = "b16e6bc0fc7e6a218583f40c7d201771f2e3072f85ef6e9217b36c1dc6b2aa25";
  };
  libass = {
    version = "0.17.1";
    url = "https://github.com/libass/libass/releases/download/0.17.1/libass-0.17.1.tar.xz";
    sha256 = "f0da0bbfba476c16ae3e1cfd862256d30915911f7abaa1b16ce62ee653192784";
  };
  libogg = {
    version = "1.3.5";
    url = "https://github.com/xiph/ogg/releases/download/v1.3.5/libogg-1.3.5.tar.gz";
    sha256 = "0eb4b4b9420a0f51db142ba3f9c64b333f826532dc0f48c6410ae51f4799b664";
  };
  libplacebo = {
    version = "7.349.0";
    url = "https://github.com/haasn/libplacebo/archive/refs/tags/v7.349.0.tar.gz";
    sha256 = "627e32439a0b3d2b90368ead7e919f470ee7446c87cc0f7841bbe319b23aa8b1";
  };
  # libplacebo vendors these as git submodules, which are NOT included in
  # GitHub's auto-generated source archives, so they have to be fetched and
  # unpacked into ./3rdparty by hand (see nix/packages/mk-pkg-libplacebo).
  libplacebo-3rdparty-fast_float = {
    version = "5.2.0";
    url = "https://github.com/fastfloat/fast_float/archive/refs/tags/v5.2.0.tar.gz";
    sha256 = "72bbfd1914e414c920e39abdc81378adf910a622b62c45b4c61d344039425d18";
  };
  libplacebo-3rdparty-glad = {
    version = "2.0.4";
    url = "https://github.com/Dav1dde/glad/archive/refs/tags/v2.0.4.tar.gz";
    sha256 = "02629644c242dcc27c58222bd2c001d5e2f3765dbbcfd796542308bddebab401";
  };
  libplacebo-3rdparty-jinja = {
    version = "3.1.2";
    url = "https://github.com/pallets/jinja/archive/refs/tags/3.1.2.tar.gz";
    sha256 = "ecae76cd1a064d40eb46c5375f07953d747f4d65b68cd3fa5f02c91714b799fc";
  };
  libplacebo-3rdparty-markupsafe = {
    version = "2.1.2";
    url = "https://github.com/pallets/markupsafe/releases/download/2.1.2/MarkupSafe-2.1.2.tar.gz";
    sha256 = "abcabc8c2b26036d62d4c746381a6f7cf60aafcc653198ad678306986b09450d";
  };
  libplacebo-3rdparty-vulkan-headers = {
    version = "1.3.243";
    url = "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v1.3.243.tar.gz";
    sha256 = "76c57490740369a26d68dd26d308e2faa2e0fc5d255498aa48ee389534fc5a48";
  };
  # Vulkan-Headers for the Vulkan route ONLY (kept separate from the 1.3.243
  # entry above so the baseline OpenGL build stays byte-for-byte unchanged).
  # libplacebo 7.360.1 hard-requires VK_VERSION_1_4 in vulkan_core.h:
  #   src/vulkan/meson.build:
  #     cc.has_header_symbol('vulkan/vulkan_core.h', 'VK_VERSION_1_4', ...)
  # With 1.3.243 headers that check fails, libplacebo is then configured
  # WITHOUT vulkan (silently: components['vulkan'] = false -> pl_has_vulkan=0),
  # and mpv aborts with 'libplacebo compiled without vulkan support!'.
  # Same tag + hash as mpv_kit's native/build/deps.sh (VK_SDK=1.4.363.0).
  vulkan-sdk-headers = {
    version = "1.4.363.0";
    url = "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz";
    sha256 = "4a078be12bef21cfebc09d878b77a63cff9d68f899254a0b00d0e37ef73e7f7e";
  };
  libpng = {
    version = "1.6.40";
    url = "https://github.com/pnggroup/libpng/archive/v1.6.40.tar.gz";
    sha256 = "62d25af25e636454b005c93cae51ddcd5383c40fa14aa3dae8f6576feb5692c2";
  };
  libpngPatch = {
    version = "1.6.40-1";
    url = "https://wrapdb.mesonbuild.com/v2/libpng_1.6.40-1/get_patch";
    sha256 = "bad558070e0a82faa5c0ae553bcd12d49021fc4b628f232a8e58c3fbd281aae1";
  };
  libvorbis = {
    version = "1.3.7";
    url = "https://github.com/xiph/vorbis/releases/download/v1.3.7/libvorbis-1.3.7.tar.gz";
    sha256 = "0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab";
  };
  libvpx = {
    version = "1.13.0+1";
    url = "https://gitlab.freedesktop.org/gstreamer/meson-ports/libvpx/-/archive/90d26fac0d895969a82cd873ad36e39737104c44/libvpx-v1.13.0.tar.gz";
    sha256 = "4f872ad2709d17b848b3588231495e432c42b9263731b9121fa210a3c5a893ff";
  };
  libx264 = {
    version = "a8b68ebf";
    url = "https://code.videolan.org/videolan/x264/-/archive/a8b68ebfaa68621b5ac8907610d3335971839d52/libx264-a8b68ebfaa68621b5ac8907610d3335971839d52.tar.gz";
    sha256 = "164688b63f11a6e4f6d945057fc5c57d5eefb97973d0029fb0303744e10839ff";
  };
  libxml2 = {
    version = "2.11.5";
    url = "https://download.gnome.org/sources/libxml2/2.11/libxml2-2.11.5.tar.xz";
    sha256 = "3727b078c360ec69fa869de14bd6f75d7ee8d36987b071e6928d4720a28df3a6";
  };
  mbedtls = {
    version = "3.4.1";
    url = "https://github.com/Mbed-TLS/mbedtls/archive/refs/tags/v3.4.1.tar.gz";
    sha256 = "a420fcf7103e54e775c383e3751729b8fb2dcd087f6165befd13f28315f754f5";
  };
  mpv = {
    version = "0.41.0";
    url = "https://github.com/mpv-player/mpv/archive/refs/tags/v0.41.0.tar.gz";
    # mpv 0.41.0 is pinned by NAR hash (SRI) rather than raw tarball hash.
    # This value is taken verbatim from nixpkgs' `mpv-unwrapped`
    # (pkgs/by-name/mp/mpv-unwrapped/package.nix), which pins version 0.41.0
    # via fetchFromGitHub and therefore uses the same NAR/extracted-tree
    # hashing scheme as `pkgs.fetchzip` in nix/utils/fetch-tarball.
    narHash = "sha256-gJWqfvPE6xOKlgj2MzZgXiyOKxksJlY/tL6T/BeG19c=";
  };
  uchardet = {
    version = "0.0.8";
    url = "https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz";
    sha256 = "e97a60cfc00a1c147a674b097bb1422abd9fa78a2d9ce3f3fdcc2e78a34ac5f0";
  };
}
