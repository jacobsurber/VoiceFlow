.PHONY: help build build-notarize install test clean reset-permissions setup-local-signing release dmg

SCRIPTS := scripts

# Default target
help:
	@echo "Whisp Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  install            - Build and install Whisp to /Applications/ (recommended)"
	@echo "  setup-local-signing - Create a stable local signing identity for development builds"
	@echo "  reset-permissions  - Reset and re-grant Whisp privacy permissions"
	@echo "  build              - Build the release app bundle"
	@echo "  build-notarize     - Build and notarize both app bundles"
	@echo "  test               - Run tests"
	@echo "  clean              - Clean build artifacts"
	@echo "  dmg                - Create a local DMG from the built app bundles"
	@echo "  release            - Build a notarized DMG and create a GitHub release"

# Build and install Whisp to /Applications/
install:
	$(SCRIPTS)/install-whisp.sh

# Reset accessibility permissions (fixes Smart Paste after rebuild)
reset-permissions:
	$(SCRIPTS)/reset-accessibility.sh

# Create a persistent local signing identity so privacy permissions survive rebuilds
setup-local-signing:
	$(SCRIPTS)/setup-local-signing.sh

# Build the app
build:
	$(SCRIPTS)/build.sh

# Build and notarize the app
build-notarize:
	$(SCRIPTS)/build.sh --notarize

# Run tests
test:
	$(SCRIPTS)/run-tests.sh

# Clean build artifacts
clean:
	rm -rf .build
	rm -rf Whisp.app
	rm -rf "Uninstall Whisp.app"
	rm -f Whisp.zip
	rm -f *.sha256
	rm -f *.dmg

# Create a DMG for distribution
dmg:
	$(SCRIPTS)/create-dmg.sh

# Create a new release
release:
	@VERSION=$$(cat VERSION | tr -d '[:space:]'); \
	TAG="v$$VERSION"; \
	CURRENT_COMMIT=$$(git rev-parse HEAD); \
	DMG_NAME="Whisp-$$VERSION.dmg"; \
	CHECKSUM_NAME="Whisp-$$VERSION.dmg.sha256"; \
	LOCAL_TAG_COMMIT=""; \
	REMOTE_TAG_COMMIT=""; \
	echo "Creating release $$TAG from $$CURRENT_COMMIT..."; \
	if [ -z "$$(git status --porcelain --untracked-files=normal)" ]; then \
		if gh release view "$$TAG" >/dev/null 2>&1; then \
			echo "❌ Error: Release $$TAG already exists."; \
			exit 1; \
		fi; \
		if git rev-parse "$$TAG" >/dev/null 2>&1; then \
			LOCAL_TAG_COMMIT=$$(git rev-list -n 1 "$$TAG"); \
		fi; \
		REMOTE_TAG_COMMIT=$$(git ls-remote --tags origin "refs/tags/$$TAG" | awk '{print $$1}'); \
		if [ -n "$$LOCAL_TAG_COMMIT" ] && [ "$$LOCAL_TAG_COMMIT" != "$$CURRENT_COMMIT" ]; then \
			echo "❌ Error: Local tag $$TAG points to $$LOCAL_TAG_COMMIT, not $$CURRENT_COMMIT."; \
			exit 1; \
		fi; \
		if [ -n "$$REMOTE_TAG_COMMIT" ] && [ "$$REMOTE_TAG_COMMIT" != "$$CURRENT_COMMIT" ]; then \
			echo "❌ Error: Remote tag $$TAG points to $$REMOTE_TAG_COMMIT, not $$CURRENT_COMMIT."; \
			exit 1; \
		fi; \
		$(SCRIPTS)/build.sh --notarize && \
		$(SCRIPTS)/create-dmg.sh --notarize && \
		shasum -a 256 "$$DMG_NAME" > "$$CHECKSUM_NAME" && \
		if [ -z "$$LOCAL_TAG_COMMIT" ]; then git tag "$$TAG" "$$CURRENT_COMMIT"; fi && \
		if [ -z "$$REMOTE_TAG_COMMIT" ]; then git push origin "$$TAG"; fi && \
		gh release create "$$TAG" "$$DMG_NAME" "$$CHECKSUM_NAME" --verify-tag --target "$$CURRENT_COMMIT" --title "$$TAG" --generate-notes && \
		echo "✅ Release $$TAG created"; \
	else \
		echo "❌ Error: Working directory is not clean. Commit, stash, or remove tracked and untracked changes first."; \
		exit 1; \
	fi
