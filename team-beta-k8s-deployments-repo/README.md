# team-beta-k8s-deployments

This folder represents team-beta's k8s deployment repository in the local MVP.

Choose where each app runs by committing the corresponding values files:

| Files under `<app>/` | Where the app runs |
| --- | --- |
| `staging/app.yaml` only | Staging only |
| `production/app.yaml` only | Production only |
| Both files | Both environments |
