# ============================================================================
#  HoneygainKeeper — gestor del LaunchAgent de Honeygain (macOS 26+)
#  Atajos: `make` muestra la ayuda, `make run` compila y abre la app.
# ============================================================================

SHELL      := /bin/bash
APP        := HoneygainKeeper
SCHEME     := HoneygainKeeper
PROJECT    := HoneygainKeeper.xcodeproj
BUILD_DIR  := build
DERIVED    := $(BUILD_DIR)/DerivedData
APP_DEBUG  := $(DERIVED)/Build/Products/Debug/$(APP).app
APP_RELEASE:= $(DERIVED)/Build/Products/Release/$(APP).app
XCB        := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=macOS' -derivedDataPath $(DERIVED) -quiet

.DEFAULT_GOAL := help

.PHONY: help doctor build release run dist check logs agent-status open clean

help: ## Muestra esta ayuda
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mHoneygainKeeper\033[0m — comandos disponibles:\n\n"} \
	     /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@printf "  Primer paso:  \033[1mmake run\033[0m\n\n"

doctor: ## Comprueba macOS 26+, Xcode 26+ y Python 3
	@printf "macOS: "; sw_vers -productVersion
	@os_major=$$(sw_vers -productVersion | cut -d. -f1); \
	if [ "$$os_major" -ge 26 ]; then echo "✅ macOS $$os_major (se requiere 26+)"; \
	else echo "❌ macOS $$os_major — se requiere macOS 26 (Tahoe) o superior"; exit 1; fi
	@xcodebuild -version 2>/dev/null | head -2 || { echo "❌ Xcode no encontrado"; exit 1; }
	@swift --version | head -1
	@python3 --version >/dev/null 2>&1 && python3 --version || echo "⚠️  Python 3 no encontrado (solo necesario para 'make check')"
	@echo "✅ Entorno listo."

build: ## Compila la app en Debug
	@echo "⏳ Compilando (Debug)…"
	@$(XCB) build
	@echo "✅ Debug: $(APP_DEBUG)"

release: ## Compila la app en Release
	@echo "⏳ Compilando (Release)…"
	@$(XCB) -configuration Release build
	@echo "✅ Release: $(APP_RELEASE)"

dist: release ## Empaqueta Release en dist/ (DMG + ZIP para GitHub Releases)
	@scripts/package.sh

run: build ## Compila (Debug) y abre la app
	@open "$(APP_DEBUG)"

check: ## Paridad de localización + compilación (lo que corre CI)
	@python3 scripts/check_localization.py
	@$(MAKE) --no-print-directory build
	@echo "✅ check completo."

logs: ## Sigue el registro del servicio
	tail -f "$$HOME/Library/Logs/honeygain-keepalive.log"

agent-status: ## Estado del LaunchAgent en launchd
	@launchctl print "gui/$$(id -u)/com.yanx.honeygain-keepalive" 2>/dev/null | head -20 \
		|| echo "El LaunchAgent no está cargado."

open: ## Abre el proyecto en Xcode
	open $(PROJECT)

clean: ## Borra artefactos de compilación
	@rm -rf $(BUILD_DIR)
	@echo "✅ Limpio."
