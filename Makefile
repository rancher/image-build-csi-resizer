SEVERITIES = HIGH,CRITICAL
VEX_REPORT = rancher.openvex.json
VEX_REPORT_META = rancher.openvex.json.meta
VEX_REPORT_DIR = /tmp
VEX_REPORT_FALLBACK_DIR = .
VEX_REPORT_META_URL = https://raw.githubusercontent.com/rancher/vexhub/refs/heads/main/reports/rancher.openvex.json
VEX_REPORT_URL = https://github.com/rancher/vexhub/raw/refs/heads/main/reports/rancher.openvex.json

UNAME_M = $(shell uname -m)
ifndef TARGET_PLATFORMS
	ifeq ($(UNAME_M), x86_64)
		TARGET_PLATFORMS:=linux/amd64
	else ifeq ($(UNAME_M), aarch64)
		TARGET_PLATFORMS:=linux/arm64
	else
		TARGET_PLATFORMS:=linux/$(UNAME_M)
	endif
endif

REPO ?= ghcr.io/rancher
BUILD_META=-build$(shell date +%Y%m%d)
TAG ?= ${GITHUB_ACTION_TAG}

ifeq ($(TAG),)
TAG := $(shell cat TAG)$(BUILD_META)
endif

ifeq (,$(filter %$(BUILD_META),$(TAG)))
$(error TAG $(TAG) needs to end with build metadata: $(BUILD_META))
endif

.PHONY: build-image-csi-resizer
build-image-csi-resizer: IMAGE = $(REPO)/hardened-csi-resizer:$(TAG)
build-image-csi-resizer:
	docker buildx build \
		--platform=$(TARGET_PLATFORMS) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--target csi-resizer \
		--tag $(IMAGE) \
		--load \
	.

.PHONY: push-image-csi-resizer
push-image-csi-resizer: IMAGE = $(REPO)/hardened-csi-resizer:$(TAG)
push-image-csi-resizer:
	docker buildx build \
		$(IID_FILE_FLAG) \
		--sbom=true \
		--attest type=provenance,mode=max \
		--platform=$(TARGET_PLATFORMS) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--target csi-resizer \
		--tag $(IMAGE) \
		--push \
		.

.PHONY: image-scan
image-scan:
	@set -eu; \
	if [ -z "$${TRIVY_VEX+x}" ]; then \
		vex_report="$(VEX_REPORT_DIR)/$(VEX_REPORT)"; \
		vex_report_meta="$(VEX_REPORT_DIR)/$(VEX_REPORT_META)"; \
		if ! touch "$$vex_report" "$$vex_report_meta" 2>/dev/null; then \
			echo "Warning: shared VEX cache is not writable; using repository-local cache"; \
			vex_report="$(VEX_REPORT_FALLBACK_DIR)/$(VEX_REPORT)"; \
			vex_report_meta="$(VEX_REPORT_FALLBACK_DIR)/$(VEX_REPORT_META)"; \
		fi; \
		remote_sha="$$(curl --fail --silent --show-error --location "$(VEX_REPORT_META_URL)" | sha256sum | awk '{print $$1}')"; \
		local_sha="$$(sha256sum "$$vex_report_meta" 2>/dev/null | awk '{print $$1}' || true)"; \
		if [ "$$remote_sha" != "$$local_sha" ] || [ ! -s "$$vex_report" ]; then \
			curl --fail --silent --show-error --location "$(VEX_REPORT_URL)" > "$$vex_report"; \
			curl --fail --silent --show-error --location "$(VEX_REPORT_META_URL)" > "$$vex_report_meta"; \
		fi; \
		if [ -s "$$vex_report" ]; then \
			export TRIVY_VEX="$$vex_report"; \
		fi; \
	fi; \
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(REPO)/hardened-csi-resizer:$(TAG)

.PHONY: log
log:
	@echo "TARGET_PLATFORMS=$(TARGET_PLATFORMS)"
	@echo "REPO=$(REPO)"
	@echo "TAG=$(TAG:$(BUILD_META)=)"
	@echo "BUILD_META=$(BUILD_META)"
	@echo "UNAME_M=$(UNAME_M)"
