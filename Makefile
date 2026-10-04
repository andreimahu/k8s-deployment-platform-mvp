CLUSTER_NAME ?= k8s-deployment-platform
WAIT ?= 120s
ARGOCD_VERSION ?= v3.5.3
ARGOCD_WAIT ?= 300s
ARGOCD_PORT ?= 9090
KUBECONFIG_PATH ?= $(CURDIR)/.kube/$(CLUSTER_NAME).yaml
KUBECTL = kubectl --kubeconfig "$(KUBECONFIG_PATH)" --context "kind-$(CLUSTER_NAME)"
SAMPLE_APP_DIR ?= $(CURDIR)/sample-app
SAMPLE_IMAGE_TAG ?= local
SAMPLE_WEB_IMAGE ?= sample-app-web:$(SAMPLE_IMAGE_TAG)
SAMPLE_API_IMAGE ?= sample-app-api:$(SAMPLE_IMAGE_TAG)

.DEFAULT_GOAL := help
.PHONY: help up down sample-images argocd-bootstrap argocd-password argocd-ui argocd-ui-stop check-kind check-docker check-kubectl check-kubeconfig

help:
	@printf '%s\n' \
		'make up                                       Start kind, build/load sample images, and start Argo CD with UI forwarding' \
		'make down                                     Destroy the cluster and remove the .kube directory' \
		'make sample-images                            Build and load sample app images into an existing cluster' \
		'make up SAMPLE_IMAGE_TAG=demo                 Set the sample app image tag' \
		'make argocd-bootstrap                         Apply team namespaces, projects, and ApplicationSets' \
		'make argocd-password                          Print the initial Argo CD admin password' \
		'make argocd-ui                                Forward the Argo CD UI to https://localhost:9090' \
		'make argocd-ui-stop                           Stop background UI forwarding' \
		'make argocd-ui ARGOCD_PORT=9090               Use a custom local UI port' \
		'make up CLUSTER_NAME=k8s-deployment-platform  Set a custom cluster name' \
		'make up WAIT=120s                             Set the cluster readiness timeout' \
		'make up ARGOCD_VERSION=v3.5.3                 Set the Argo CD release' \
		'make up ARGOCD_WAIT=300s                      Set the Argo CD rollout timeout'

up: check-kind check-kubectl check-docker
	@umask 077; \
	mkdir -p "$$(dirname "$(KUBECONFIG_PATH)")" || exit $$?; \
	clusters="$$(kind get clusters)" || exit $$?; \
	if printf '%s\n' "$$clusters" | grep -Fxq -- "$(CLUSTER_NAME)"; then \
		printf 'Cluster "%s" already exists.\n' "$(CLUSTER_NAME)"; \
		kind export kubeconfig --name "$(CLUSTER_NAME)" --kubeconfig "$(KUBECONFIG_PATH)"; \
	else \
		kind create cluster --name "$(CLUSTER_NAME)" --wait "$(WAIT)" --kubeconfig "$(KUBECONFIG_PATH)"; \
	fi
	@$(MAKE) --no-print-directory sample-images
	@printf '%s\n' 'apiVersion: v1' 'kind: Namespace' 'metadata:' '  name: argocd' | \
		$(KUBECTL) apply -f -
	$(KUBECTL) -n argocd apply --server-side --force-conflicts \
		-f "https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGOCD_VERSION)/manifests/install.yaml"
	$(KUBECTL) -n argocd rollout status deployment \
		-l app.kubernetes.io/part-of=argocd --timeout="$(ARGOCD_WAIT)"
	$(KUBECTL) -n argocd rollout status statefulset/argocd-application-controller \
		--timeout="$(ARGOCD_WAIT)"
	@$(MAKE) --no-print-directory argocd-bootstrap
	@printf '\nArgo CD admin credentials:\nUsername: admin\nPassword: '
	@$(MAKE) --no-print-directory argocd-password
	@$(MAKE) --no-print-directory argocd-ui

down: check-kind
	@$(MAKE) --no-print-directory argocd-ui-stop
	kind delete cluster --name "$(CLUSTER_NAME)" --kubeconfig "$(KUBECONFIG_PATH)"
	rm -f -- "$(KUBECONFIG_PATH)"
	rm -rf -- "$(CURDIR)/.kube"

sample-images: check-kind check-docker
	docker build -f "$(SAMPLE_APP_DIR)/apps/web/Dockerfile" -t "$(SAMPLE_WEB_IMAGE)" "$(SAMPLE_APP_DIR)"
	docker build -f "$(SAMPLE_APP_DIR)/apps/api/Dockerfile" -t "$(SAMPLE_API_IMAGE)" "$(SAMPLE_APP_DIR)"
	kind load docker-image "$(SAMPLE_WEB_IMAGE)" "$(SAMPLE_API_IMAGE)" --name "$(CLUSTER_NAME)"

argocd-bootstrap: check-kubectl check-kubeconfig
	$(KUBECTL) apply -f platform/argocd/namespaces.yaml
	$(KUBECTL) apply -f platform/argocd/projects/
	$(KUBECTL) -n argocd set env deployment/argocd-applicationset-controller \
		ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_NEW_GIT_FILE_GLOBBING=true
	$(KUBECTL) -n argocd rollout status deployment/argocd-applicationset-controller \
		--timeout="$(ARGOCD_WAIT)"
	$(KUBECTL) apply -f platform/argocd/applicationsets/

argocd-password: check-kubectl check-kubeconfig
	@$(KUBECTL) -n argocd get secret argocd-initial-admin-secret \
		-o go-template='{{index .data "password" | base64decode}}{{"\n"}}'

argocd-ui: check-kubectl check-kubeconfig
	@sh scripts/argocd-ui.sh start "$(CLUSTER_NAME)" "$(KUBECONFIG_PATH)" "$(ARGOCD_PORT)" "$(CURDIR)/.kube"

argocd-ui-stop:
	@sh scripts/argocd-ui.sh stop "$(CLUSTER_NAME)" "$(KUBECONFIG_PATH)" "$(ARGOCD_PORT)" "$(CURDIR)/.kube"

check-kind:
	@command -v kind >/dev/null 2>&1 || { \
		printf '%s\n' 'Error: kind is required. See https://kind.sigs.k8s.io/docs/user/quick-start/' >&2; \
		exit 1; \
	}

check-docker:
	@command -v docker >/dev/null 2>&1 || { \
		printf '%s\n' 'Error: Docker is required to build the sample app images.' >&2; \
		exit 1; \
	}

check-kubectl:
	@command -v kubectl >/dev/null 2>&1 || { \
		printf '%s\n' 'Error: kubectl is required. See https://kubernetes.io/docs/tasks/tools/' >&2; \
		exit 1; \
	}

check-kubeconfig:
	@test -r "$(KUBECONFIG_PATH)" || { \
		printf 'Error: kubeconfig "%s" is missing or unreadable. Run make up CLUSTER_NAME=%s first.\n' \
			"$(KUBECONFIG_PATH)" "$(CLUSTER_NAME)" >&2; \
		exit 1; \
	}
