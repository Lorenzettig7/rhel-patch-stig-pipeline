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

kind-load:
	kind load docker-image $(IMAGE) --name $(CLUSTER)

# The chart only accepts a digest, so read the manifest digest containerd
# recorded for the loaded image on the kind node and deploy that. pullPolicy
# Never: the image only exists locally, so a miss should fail, not hit a registry.
kind-install:
	@digest=$$(docker exec $(KIND_NODE) crictl inspecti -o go-template \
	    --template '{{range .status.repoDigests}}{{println .}}{{end}}' docker.io/library/$(IMAGE) \
	    | grep -oE 'sha256:[a-f0-9]{64}' | head -1); \
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
