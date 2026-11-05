# Path to the Xcode.app bundle. If not set, the overlay will fall back to
# fetching Xcode from the Nix store (requires manual download, see
# nix/overlays/xcode.nix for instructions).
# Example: make XCODE_PATH=/Applications/Xcode_16.1.0.app
XCODE_PATH ?=

# Version string to build. If not set, falls back to .nix/config/version.txt.
# Example: make VERSION=0.0.1
VERSION ?=

# Flake output attribute to build. If not set, the default package is built.
# Example: make TARGET=mk-out-archive-libs-macos-universal-video-default
TARGET ?=

all: build

# Build using Nix flakes.
# After the build, .nix/config/xcode.path and .nix/config/version.txt are
# restored to their previous values.
#
# NOTE: this used to be done with `git checkout --`, which requires a git
# work tree. This source tree may be shipped as a plain archive (no .git),
# in which case that restore silently failed and left the config files dirty,
# so the values are now saved and restored explicitly instead.
.PHONY: build
build:
	@set -e; \
	backup_dir=$$(mktemp -d); \
	trap 'cp -f "$$backup_dir/xcode.path" .nix/config/xcode.path; \
	      cp -f "$$backup_dir/version.txt" .nix/config/version.txt; \
	      rm -rf "$$backup_dir"' EXIT; \
	cp -f .nix/config/xcode.path "$$backup_dir/xcode.path"; \
	cp -f .nix/config/version.txt "$$backup_dir/version.txt"; \
	$(if $(XCODE_PATH),echo '$(XCODE_PATH)' > .nix/config/xcode.path;,) \
	$(if $(VERSION),echo '$(VERSION)' > .nix/config/version.txt;,) \
	nix build -v -L \
		--option sandbox true \
		--option sandbox-fallback false \
		$(if $(XCODE_PATH),--option extra-sandbox-paths $(XCODE_PATH),) \
		$(if $(TARGET),.#$(TARGET),)
