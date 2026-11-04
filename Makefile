IMAGE ?= secure-python-api
TAG   ?= local

.PHONY: build run scan lint sbom naive compare

build:            ## Build the hardened image
	docker build -t $(IMAGE):$(TAG) .

run: build        ## Run it with production-style hardening
	docker compose up --build

lint:             ## Lint the Dockerfile
	docker run --rm -i hadolint/hadolint:v2.15.1 < Dockerfile

scan: build       ## Scan for HIGH/CRITICAL vulnerabilities
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
	aquasec/trivy:0.76.1 image --severity HIGH,CRITICAL --ignore-unfixed $(IMAGE):$(TAG)

sbom: build       ## Software bill of materials (SPDX)
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
	aquasec/trivy:0.76.1 image --format spdx-json $(IMAGE):$(TAG) > sbom.spdx.json

naive:            ## Build the bad example, for comparison
	docker build -f Dockerfile.naive -t $(IMAGE):naive .

compare: build naive  ## Image size, side by side
	@docker image ls $(IMAGE) --format 'table {{.Tag}}\t{{.Size}}'
