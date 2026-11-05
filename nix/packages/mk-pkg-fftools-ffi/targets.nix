# fftools-ffi is currently DISABLED.
#
# Upstream (moffatman/fftools-ffi) vendors a fork of FFmpeg's fftools from the
# FFmpeg 6 era. Pinned commit 9b0d4da0 is its current HEAD, and it does not
# compile against FFmpeg 7.0.2: the macOS/iOS CI build stops in this package
# with libav* deprecation/removal errors, and every downstream output
# (mk-out-libs, mk-out-archive-libs, mk-out-all) fails as a consequence.
#
# The melodink reference build, which also uses FFmpeg 7.0.2, dropped this
# component for the same reason.
#
# Returning an empty list keeps nix/utils/flake/packages-with-targets.nix from
# publishing any fftools-ffi output, while default.nix and the packages.lock.nix
# entry stay in place. To re-enable it once it has been ported to FFmpeg 7,
# restore this file to:
#
#   import ../../utils/targets/pkgs.nix
#
# and re-add fftoolsFfi to the encodersgpl dependency list in
# ../mk-out-libs/default.nix.
[ ]
