# Builds MTMR.app with only the Xcode Command Line Tools (no Xcode needed).
#
#   make            build build/MTMR.app for this Mac's architecture
#   make universal  build an arm64 + x86_64 app
#   make run        build, then (re)launch it
#   make install    copy to /Applications (replacing any existing MTMR.app)
#   make clean

APP_NAME    := MTMR
BUNDLE_ID   ?= Toxblh.MTMR
MIN_MACOS   := 11.0
ARCHS       ?= $(shell uname -m)

BUILD       := build
APP         := $(BUILD)/$(APP_NAME).app
CONTENTS    := $(APP)/Contents
OBJ         := $(BUILD)/obj

SDK         := $(shell xcrun --show-sdk-path)
SRC         := MTMR
BRIDGE_HDR  := $(SRC)/CBridge/TouchBarPrivateApi-Bridging.h
SWIFT_SRCS  := $(shell find $(SRC) -name '*.swift')
C_SRCS      := $(wildcard $(SRC)/CBridge/*.m $(SRC)/CBridge/*.c)
ASSETS      := $(SRC)/Assets.xcassets

FW_FLAGS    := -F . -F build-support/Frameworks -F $(SDK)/System/Library/PrivateFrameworks
FRAMEWORKS  := -framework Sparkle -framework DFRFoundation -framework MultitouchSupport \
               -framework CoreBrightness -framework CoreDisplay \
               -framework Cocoa -framework Carbon -framework IOKit -framework ServiceManagement

.PHONY: all universal run install clean
all: $(APP)

universal:
	$(MAKE) ARCHS="arm64 x86_64"

# One executable per arch, then lipo them together.
$(BUILD)/$(APP_NAME): $(SWIFT_SRCS) $(C_SRCS) $(wildcard $(SRC)/CBridge/*.h) Makefile
	@mkdir -p $(OBJ)
	@for arch in $(ARCHS); do \
	  echo "==> compiling $$arch"; \
	  target=$$arch-apple-macos$(MIN_MACOS); \
	  mkdir -p $(OBJ)/$$arch; \
	  for f in $(C_SRCS); do \
	    clang -c -target $$target -isysroot $(SDK) -fobjc-arc -fmodules -O2 -w \
	      -I $(SRC)/CBridge $$f -o $(OBJ)/$$arch/$$(basename $$f).o || exit 1; \
	  done; \
	  swiftc -target $$target -sdk $(SDK) -O -swift-version 5 \
	    -module-name $(APP_NAME) -import-objc-header $(BRIDGE_HDR) -I $(SRC)/CBridge \
	    $(FW_FLAGS) $(FRAMEWORKS) \
	    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
	    $(SWIFT_SRCS) $(OBJ)/$$arch/*.o -o $(OBJ)/$$arch/$(APP_NAME) || exit 1; \
	done
	lipo -create $(foreach a,$(ARCHS),$(OBJ)/$(a)/$(APP_NAME)) -output $@

$(APP): $(BUILD)/$(APP_NAME) $(SRC)/Info.plist $(SRC)/MTMR.entitlements
	@rm -rf $(APP) && mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources $(CONTENTS)/Frameworks
	cp $(BUILD)/$(APP_NAME) $(CONTENTS)/MacOS/
	@# Info.plist: substitute the Xcode build-setting variables.
	sed -e 's/$$(EXECUTABLE_NAME)/$(APP_NAME)/g' -e 's/$$(PRODUCT_NAME)/$(APP_NAME)/g' \
	    -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/$(BUNDLE_ID)/g' -e 's/$$(DEVELOPMENT_LANGUAGE)/en/g' \
	    -e 's/$$(MACOSX_DEPLOYMENT_TARGET)/$(MIN_MACOS)/g' $(SRC)/Info.plist > $(CONTENTS)/Info.plist
	/usr/libexec/PlistBuddy -c 'Delete :NSMainStoryboardFile' $(CONTENTS)/Info.plist
	/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile AppIcon' $(CONTENTS)/Info.plist
	@# Resources: loose copies of the asset catalog images (no actool), scripts, preset.
	@for set in $(ASSETS)/*.imageset; do \
	  name=$$(basename $$set .imageset); \
	  for f in $$set/*.png $$set/*.pdf; do if [ -f "$$f" ]; then cp "$$f" "$(CONTENTS)/Resources/$$name.$${f##*.}"; fi; done; \
	done
	@iconset=$(BUILD)/AppIcon.iconset; rm -rf $$iconset && mkdir -p $$iconset; \
	for s in 16 32 128 256 512; do \
	  cp $(ASSETS)/AppIcon.appiconset/logo-$$s.png $$iconset/icon_$${s}x$${s}.png; \
	  d=$$((s*2)); if [ -f $(ASSETS)/AppIcon.appiconset/logo-$$d.png ]; then cp $(ASSETS)/AppIcon.appiconset/logo-$$d.png $$iconset/icon_$${s}x$${s}@2x.png; fi; \
	done; iconutil -c icns $$iconset -o $(CONTENTS)/Resources/AppIcon.icns
	cp $(SRC)/defaultPreset.json $(SRC)/dsa_pub.pem $(CONTENTS)/Resources/
	cp -R $(SRC)/AppleScripts/ $(CONTENTS)/Resources/
	cp -R Sparkle.framework $(CONTENTS)/Frameworks/
	codesign --force --deep --sign - --entitlements $(SRC)/MTMR.entitlements $(APP)
	@echo "==> built $(APP)"

run: $(APP)
	-pkill -x $(APP_NAME); sleep 1
	open $(APP)

install: $(APP)
	-pkill -x $(APP_NAME); sleep 1
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/
	open /Applications/$(APP_NAME).app

clean:
	rm -rf $(BUILD)
