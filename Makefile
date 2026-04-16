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
	@echo "  build-notarize     - Build and notarize the app"
	@echo "  test               - Run tests"
	@echo "  clean              - Clean build artifacts"
	@echo "  dmg                - Create a DMG for distribution"
	@echo "  release            - Create a new GitHub release"

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
	rm -f Whisp.zip
	rm -f *.dmg

# Create a DMG for distribution
dmg:
	$(SCRIPTS)/create-dmg.sh

# Create a new release
release:
	@VERSION=$$(cat VERSION | tr -d '[:space:]'); \
	echo "Creating release v$$VERSION..."; \
	if git diff --quiet && git diff --cached --quiet; then \
		$(SCRIPTS)/build.sh && \
		zip -r Whisp.zip Whisp.app && \
		gh release create "v$$VERSION" Whisp.zip --title "v$$VERSION" --generate-notes && \
		echo "✅ Release v$$VERSION created"; \
	else \
		echo "❌ Error: Working directory is not clean. Commit or stash changes first."; \
		exit 1; \
	fi
