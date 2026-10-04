# k8s-deployment-platform-mvp
Local GitOps k8s deployment platform MVP using `kind`, `ArgoCD` and `Helm`.
For readability and ease of use everything is contained in this single repo.

`Team alpha` and `team beta` each have their own directory which could be
equivalent to separate git repositories in a production implementation.

Each team has an ArgoCD `AppProject` and `ApplicationSet` with staging and production
namespaces on the same cluster. When a team is onboarded to the platform, the platform
team will be responsible for creating these resources.

Helm chart values files in each teams directory determine which apps and to
what environments they are deployed. Removing or renaming the Helm values file
will remove the app in question from the k8s cluster.

**MVP limitations include a single fixed Helm chart, fixed credentials,
local container images, no monitoring and automatic production sync without approval gates or guardrails.**

## Proposed paved road
### In the context of the MVP and it's limitations
Consider team-alpha and their `team-alpha-k8s-deployments-repo`

To deploy an app, create `<app>/staging/app.yaml`, `<app>/production/app.yaml` or
both. These are values files for the single fixed `three-tier-app` Helm chart.

Populate with `image`, `replica` count and other `configuration` for each component, commit and push to `main`.
ArgoCD will then discover and sync the files and create the corresponding applications.

To remove a deployment, delete or rename the corresponding `app.yaml` file.

### For an expanded, more controlled alternative (outside of MVP scope)
Use a PR driven workflow where opening a PR validates the values and attempts
a deployment to staging.

If CI/CD passes on staging, the PR can be merged to `main` for a production
deployment.

## Running the MVP
Requires running `Docker`, `make`, `kind` and `kubectl`.

Should you need to adjust any defaults run `make help` to get a list of what is available.

Run the MVP with default settings:
```sh
make up
```
This does the following:
- creates the k8s cluster with kind
- builds and loads the sample app images
- installs Argo CD, exposes the admin credentials and port forwards the UI to localhost
- applies the `Namespace`, `AppProject` and `ApplicationSet` manifests

ArgoCD will then sync the discovered apps from the repository.

Kubeconfig is written to `.kube/k8s-deployment-platform.yaml`.

The ArgoCD UI will be available on https://localhost:9090

To access team alpha's staging sample app for example, port forward their services
and then go to http://localhost:4173
```sh
kubectl --kubeconfig .kube/k8s-deployment-platform.yaml -n team-alpha-staging \
  port-forward service/team-alpha-sample-app-staging-web 4173:4173
```
```sh
kubectl --kubeconfig .kube/k8s-deployment-platform.yaml -n team-alpha-staging \
  port-forward service/team-alpha-sample-app-staging-api 8080:8080
```

To cleanup run:
```sh
make down
```
This stops forwarding, deletes the cluster and removes the entire `.kube/` directory.

## Production implementation considerations

For a production implementation we could consider deploying multiple kubernetes clusters:
- `platform/shared-services` cluster for centrealized ArgoCD, container registry, monitoring and other internal workloads
- `staging` for end to end testing of various kinds of workloads
- `production` for customer facing production workloads

Application code repositories and CI, including building and pushing container images workflows,
could fall under the application development teams responsibilities.

The platform team will then be responsible for providing the container registry and access to it
as well as a Helm charts registry. `AWS ECR` for example can distribute both container images and
Helm charts.

The `ArgoCD Image Updater` can be used to automatically update deployed applications
container images in response to new images becoming available in the registry of choice.
Multiple strategies and constraints can be configured such as updating to the tag with
the highest allowed semantic version matching the `v1.2.3` tag format.

**Platform and application monitoring** is a must and should include logs, metrics, alerts and potentially traces.
An LGTM (Loki, Grafana, Mimir, Tempo) Monitoring Stack is an option.

**Secrets management** can be handled with kubernetes secrets,
the [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
with the AWS provider can read secrets from AWS Secrets Manager and the AWS Systems Manager Parameter Store.

[Crossplane](https://www.crossplane.io/) should be considered for provisioning cloud resources
using kubernetes manifests. This can integrate well with the Helm charts built and maintained by
the platform team.

For example, the `sample-app` using the `three-tier-app` Helm chart we built. The chart could
offer the ability to either deploy a self-hosted PostgreSQL database in kubernetes or
provision a cluster in AWS RDS. This could be achieved by using Crossplane and it's
AWS provider.
