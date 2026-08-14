.PHONY: build run clean archive dmg install

PROJECT_NAME = OwlFixWiFi
SCHEME = OwlFixWiFi
BUILD_DIR = build
VERSION = $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" OwlFixWiFi/Info.plist)
DMG_NAME = OwlFixWiFi-v$(VERSION).dmg

build:
	@echo "🛠️ 正在编译 Debug 版本 $(PROJECT_NAME)..."
	xcodebuild -project $(PROJECT_NAME).xcodeproj -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) build

release:
	@echo "🛠️ 正在编译 Release 版本 $(PROJECT_NAME)..."
	xcodebuild -project $(PROJECT_NAME).xcodeproj -scheme $(SCHEME) -configuration Release -derivedDataPath $(BUILD_DIR) build

dmg: release
	@echo "📦 正在生成 DMG 安装包 $(DMG_NAME)..."
	hdiutil create -volname "OwlFix WiFi" -srcfolder $(BUILD_DIR)/Build/Products/Release/$(PROJECT_NAME).app -ov -format UDZO $(DMG_NAME)

install: release
	@echo "🚀 正在安装 $(PROJECT_NAME) 到 /Applications..."
	rm -rf /Applications/$(PROJECT_NAME).app
	cp -R $(BUILD_DIR)/Build/Products/Release/$(PROJECT_NAME).app /Applications/$(PROJECT_NAME).app
	@echo "✅ 已成功安装至 /Applications/$(PROJECT_NAME).app"

run: build
	@echo "🚀 启动 $(PROJECT_NAME)..."
	open $(BUILD_DIR)/Build/Products/Debug/$(PROJECT_NAME).app

clean:
	@echo "🧹 清理构建产物..."
	rm -rf $(BUILD_DIR) $(DMG_NAME)

archive:
	@echo "📦 打包 $(PROJECT_NAME)..."
	xcodebuild -project $(PROJECT_NAME).xcodeproj -scheme $(SCHEME) -configuration Release -derivedDataPath $(BUILD_DIR) archive
