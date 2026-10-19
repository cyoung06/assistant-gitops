# assistant-gitops

GitOps repo for the personal assistant app on `syeyoung-kube`, applied by Flux.

```
clusters/syeyoung-kube/   Flux entry point (flux-system/ is written by `flux bootstrap`)
  apps.yaml               → apps/
apps/assistant/           API, web, Tailscale ingress, link to the host Postgres
deploy.sh                 deploys an app's newest CI image as a signed commit
```

Code: [assistant-api](https://github.com/cyoung06/assistant-api), [assistant-web](https://github.com/cyoung06/assistant-web).

Flow: push to `main` in either code repo → GitHub Actions tests and pushes
`ghcr.io/cyoung06/<image>:<run>-<sha>` → `./deploy.sh api` (or `web`) pins that image by digest in a
signed commit here → Flux applies it.

## Signed commits only

Flux applies a commit only if it is signed by syeyoung's personal key (296393DBF79539FC; the public
key is in `clusters/syeyoung-kube/flux-system/pgp-public-keys.yaml`). So control of GitHub alone
can't change the cluster: unsigned commits here are refused, and images are pinned by digest, so a
re-pushed tag isn't picked up. Nothing in the cluster pushes here; Flux's deploy key is read-only.

Flux checks only the newest commit, so `deploy.sh` first checks that every commit since the one
that turned this on (and every app commit since the last deploy) is signed by that key, and refuses
to sign on top of anything else. When committing here by hand, `git log --format='%h %G? %GP %s'`
shows the same.

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
  --branch=main --path=clusters/syeyoung-kube --private=false
unset GITHUB_TOKEN

kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=<path to the age key>
```

(The cluster was first bootstrapped with image automation, since removed; its controllers are
still installed but have nothing to do.)

## Useful commands

```sh
flux get kustomizations
flux get sources git          # "verified" when the newest commit's signature checks out
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
