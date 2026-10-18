# deploy

GitOps repo for the `assistant` app on `syeyoung-kube`, applied by Flux.

```
clusters/syeyoung-kube/   Flux entry point (flux-system/ is written by `flux bootstrap`)
  infrastructure.yaml     → infrastructure/   Gitea Actions runner for the assistant org
  apps.yaml               → apps/             the app (depends on infrastructure)
  image-automation.yaml   commits new image tags from CI back to apps/
apps/assistant/           API, web, Tailscale ingress, link to the host Postgres, image policies
```

Flow: push to `main` in `assistant/api` or `assistant/web` → Gitea Actions tests and pushes
`registry.syeyoung.dev/assistant/<image>:<run>-<sha>` → Flux sees the higher run number, commits the
new tag here, and rolls the Deployment.

The app: https://assistant.lonk-kelvin.ts.net (tailnet only).

## Secrets

`*.sops.yaml` files are encrypted with age (recipient in `.sops.yaml`). Flux decrypts them with the
`sops-age` secret in `flux-system`. The private key lives in
`~/Library/Application Support/sops/age/keys.txt`; keep a copy in Vaultwarden.

```sh
sops apps/assistant/api-secrets.sops.yaml     # view or edit in place
```

| File | Contents |
|---|---|
| `apps/assistant/api-secrets.sops.yaml` | `DB_PASSWORD`, `LLM_API_KEY` |
| `apps/assistant/regcred.sops.yaml` | Registry pull token (`assistant-serviceaccount`, `read:package`) |
| `infrastructure/gitea-runner/runner-token.sops.yaml` | Runner registration token for the `assistant` org |

Non-secret settings are in the `configMapGenerator` in `apps/assistant/kustomization.yaml`.

## Bootstrap (once)

```sh
export GITEA_TOKEN=$(cat ../secrets/flux-token)   # assistant-serviceaccount, write:repository
flux bootstrap gitea \
  --hostname=registry.syeyoung.dev --owner=assistant --repository=deploy \
  --branch=main --path=clusters/syeyoung-kube --token-auth --private=true \
  --components-extra=image-reflector-controller,image-automation-controller
unset GITEA_TOKEN

kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey="$HOME/Library/Application Support/sops/age/keys.txt"
```

## Useful commands

```sh
flux get kustomizations
flux get images all -n assistant
flux reconcile kustomization apps --with-source
kubectl -n assistant logs deploy/assistant-api
```

## Database

Postgres runs on the node (192.168.219.104:5432), outside Kubernetes; `apps/assistant/postgres.yaml`
gives it the in-cluster name `postgres`. Database and role: `assistant`. `pg_hba.conf` allows the pod
network 10.42.0.0/16. The API runs its Flyway migrations on startup.
