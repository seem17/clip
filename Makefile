.PHONY: all app run install dmg clean icon

all: app

app:
	@./scripts/build_app.sh

run:
	@./scripts/build_app.sh --run

install:
	@./scripts/build_app.sh --install

dmg:
	@./scripts/create_dmg.sh

icon:
	@swift -module-cache-path ../.cache scripts/generate_icon.swift
	@iconutil -c icns AppIcon.iconset -o Sources/Clip/Resources/AppIcon.icns
	@rm -rf AppIcon.iconset

clean:
	@rm -rf .build build
