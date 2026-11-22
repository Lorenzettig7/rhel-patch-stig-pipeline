# Local Kubernetes demo for the demo-api image (kind + Helm).
#   make kind-up     build image, create cluster, load image, install chart
#   make kind-test   smoke-test the running release
#   make kind-down   delete the cluster

CLUSTER    ?= lm-demo
NAMESPACE  ?= demo-api
RELEASE    ?= demo-api
IMAGE_REPO ?= demo-api
IMAGE_TAG  ?= local
IMAGE      := $(IMAGE_REPO):$(IMAGE_TAG)
CHART      := deploy/helm/demo-api
KIND_NODE  := $(CLUSTER)-control-plane
KUBECTL    := kubectl --context kind-$(CLUSTER)
HELM       := helm --kube-context kind-$(CLUSTER)

.PHONY: image kind-up kind-cluster kind-namespace kind-load kind-install kind-test kind-down

image:
	docker build -f app/Containerfile -t $(IMAGE) \
	  --build-arg VCS_REF=$$(git rev-parse HEAD) \
	  --build-arg BUILD_DATE=$$(date -u +%Y-%m-%dT%H:%M:%SZ) \
	  app

kind-up: image kind-cluster kind-namespace kind-load kind-install

kind-cluster:
	@kind get clusters 2>/dev/null | grep -qx '$(CLUSTER)' \
	  && echo "kind cluster $(CLUSTER) already exists" \
	  || kind create cluster --config deploy/kind-cluster.yaml --name $(CLUSTER) --wait 120s

# Pod Security Admission: reject any pod that doesn't meet "restricted".
kind-namespace:
	$(KUBECTL) create namespace $(NAMESPACE) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) label namespace $(NAMESPACE) --overwrite \
	  pod-security.kubernetes.io/enforce=restricted \
	  pod-security.kubernetes.io/enforce-version=latest \
	  pod-security.kubernetes.io/warn=restricted \
	  pod-security.kubernetes.io/audit=restricted

# Manifest digest containerd recorded for the loaded image on the kind node.
NODE_DIGEST = docker exec $(KIND_NODE) crictl inspecti -o go-template \
	  --template '{{range .status.repoDigests}}{{println .}}{{end}}' docker.io/library/$(IMAGE) \
	  | grep -oE 'sha256:[a-f0-9]{64}' | head -1

# `kind load` registers the image under its tag only, but the kubelet resolves
# repo@sha256 references by name, so also register the digest reference.
kind-load:
	kind load docker-image $(IMAGE) --name $(CLUSTER)
	@digest=$$($(NODE_DIGEST)); \
	  test -n "$$digest" || { echo "could not find digest for $(IMAGE) on $(KIND_NODE)"; exit 1; }; \
	  docker exec $(KIND_NODE) ctr -n k8s.io images tag --force \
	    docker.io/library/$(IMAGE) docker.io/library/$(IMAGE_REPO)@$$digest

# The chart only accepts a digest, so deploy the digest found on the node.
# pullPolicy Never: the image only exists locally, so a miss should fail
# rather than reach out to a registry.
kind-install:
	@digest=$$($(NODE_DIGEST)); \
	  test -n "$$digest" || { echo "could not find digest for $(IMAGE) on $(KIND_NODE)"; exit 1; }; \
	  echo "Deploying docker.io/library/$(IMAGE_REPO)@$$digest"; \
	  $(HELM) upgrade --install $(RELEASE) $(CHART) \
	    --namespace $(NAMESPACE) \
	    --set image.repository=docker.io/library/$(IMAGE_REPO) \
	    --set image.digest=$$digest \
	    --set image.pullPolicy=Never \
	    --wait --timeout 120s

kind-test:
	$(KUBECTL) -n $(NAMESPACE) get pods -o wide
	$(KUBECTL) -n default run curl-$$$$ --rm -i --restart=Never --image=curlimages/curl:8.11.1 --quiet -- \
	  sh -c 'curl -sf http://$(RELEASE).$(NAMESPACE).svc/healthz && echo && curl -sf http://$(RELEASE).$(NAMESPACE).svc/version && echo'

kind-down:
	kind delete cluster --name $(CLUSTER)
