# This makefile is mainly intended for use on the CI server (Travis).
# It requires xcpretty to be installed.

# If you are trying to build a release locally consider using the 
# makerelease.rb script in the Tools directory instead.


BUILD_DIR = OBJROOT="$(CURDIR)/build" SYMROOT="$(CURDIR)/build"
SHELL = /bin/bash -e -o pipefail
MACOSX = -scheme CCMenu -sdk macosx $(BUILD_DIR)
XCODEBUILD = xcodebuild -project "$(CURDIR)/CCMenu.xcodeproj"

ci: clean test

clean:
	$(XCODEBUILD) clean
	rm -rf "$(CURDIR)/build"

test:
	@echo "Running OS X tests..."
	$(XCODEBUILD) $(MACOSX) test | xcpretty -c
