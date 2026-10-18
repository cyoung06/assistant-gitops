# assistant-gitops

GitOps repo for the personal assistant app on `syeyoung-kube`, applied by Flux.

```
clusters/syeyoung-kube/   Flux entry point (flux-system/ is written by `flux bootstrap`)
  apps.yaml               → apps/
apps/assistant/           API, web, Tailscale ingress, link to the host Postgres, image policies
                          and the automation that commits new image tags back here
```

Code: [assistant-api](https://github.com/cyoung06/assistant-api), [assistant-web](https://github.com/cyoung06/assistant-web).

Flow: push to `main` in either code repo → GitHub Actions tests and pushes
`ghcr.io/cyoung06/<image>:<run>-<sha>` → Flux sees the higher run number, commits the new tag
here, and rolls the Deployment.

The app: https://assistant.lonk-kelvin.ts.net (tailnet only; there is no login).

## Secrets

`*.sops.yaml` files are encrypted with age (recipient in `.sops.yaml`). Flux decrypts them with the
`sops-age` secret in `flux-system`. Keep a copy of the private key somewhere safe; without it the
secrets can't be read or changed.

```sh
sops apps/assistant/api-secrets.sops.yaml     # view or edit in place
```

| File | Contents |
|---|---|
| `apps/assistant/api-secrets.sops.yaml` | `DB_PASSWORD`, `LLM_API_KEY`, `PLMS_USERNAME`, `PLMS_PASSWORD` |

Non-secret settings are in the `configMapGenerator` in `apps/assistant/kustomization.yaml`.

## Bootstrap (once)

```sh
export GITHUB_TOKEN=$(gh auth token)
flux bootstrap github \
  --owner=cyoung06 --personal --repository=assistant-gitops \
  --branch=main --path=clusters/syeyoung-kube --private=false --read-write-key \
  --components-extra=image-reflector-controller,image-automation-controller
unset GITHUB_TOKEN

kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=<path to the age key>
```

`--read-write-key` lets image automation push tag updates through the deploy key.

## Useful commands

```sh
flux get kustomizations
flux get images all -n assistant
flux reconcile kustomization apps --with-source
kubectl -n assistant logs deploy/assistant-api
```

## Database

Postgres runs on the node itself, outside Kubernetes; `apps/assistant/postgres.yaml` gives it the
in-cluster name `postgres`. Database and role: `assistant`. `pg_hba.conf` allows the pod network
10.42.0.0/16. The API runs its Flyway migrations on startup.

## Node capacity

The node has 2 CPUs and most of it is already reserved by other apps, so
`clusters/syeyoung-kube/flux-system/kustomization.yaml` lowers Flux's CPU requests and the app's
requests are kept small. Check `kubectl describe node` before adding workloads.
