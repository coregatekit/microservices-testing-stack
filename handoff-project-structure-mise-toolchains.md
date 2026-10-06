# Handoff: TicketLite polyglot monorepo — design discussion

Repo: `/Users/mac-nichapat/workspace/microservices-testing-stack` (origin `github.com/coregatekit/microservices-testing-stack`)
Branch: `main`, HEAD `0f5c4d6`, working tree **clean**.
Language with user: **Thai** (reply in Thai; code/identifiers in English).

## ⚠️ Most important rule from this session

**Discuss only. Do NOT create, move, or edit files until the user explicitly says to do it.**
Last session I scaffolded a monorepo after the user only clarified the domain. The user stopped me with "ยังไม่ได้สั่งให้ทำ" (I haven't told you to do that yet). All of that scaffold has since been removed (tree is clean at HEAD). The user is still in "talk it through" mode and said they will answer the open questions later.

## Source documents (read these, don't re-summarise)

- `domain_event_sequence_diagram.html`: **TicketLite**, the current, authoritative domain (the user confirmed this). It covers 19 domain events, a transactional outbox, idempotent consumers keyed on eventId, gRPC calls between services, and a list of test cases at the end. It's a large file because of an embedded font, so strip `<style>`, `<script>` and `data:` URIs before reading.
- `tech_stack_summary.html`: the infra/tooling stack (APISIX, Keycloak 26, Postgres 16, Redis 7, OTel/Jaeger, Prometheus/Grafana/Loki, k6, the DevSecOps scanners and phases). **Outdated in two ways:** it describes the old "shop-lab" domain (Order/Catalog/Inventory/Payment) and says "Services (Go)".
- `README.md`, `K3S_SETUP.md`, `Vagrantfile`, `ansible.cfg`, `inventory.yml`, `k3s-playbook.yml`: the k3s lab cluster (Vagrant plus Ansible). `inventory.yml` points at `.vagrant/machines/...` relative to the root, so moving the Vagrantfile into a subfolder would break those paths.

## What has been decided / stated by the user

1. Make this repo a **monorepo** containing the services as well as the existing infra.
2. The domain is **TicketLite** (from the domain event file), not shop-lab.
3. The services may be **polyglot**:
   - Event Catalog: Node.js
   - Partner API: Python
   - Booking, Payment, Notification: Go
4. The user wants **mise** as the version manager for every language.

## What I proposed (discussion only, nothing implemented)

- **Contracts first.** Put the source of truth in a language-neutral `contracts/` folder: proto for gRPC and domain events, `schema.graphql` for the BFF, and OpenAPI for the Partner REST API and webhooks. Generate code per language with `buf generate` and use `buf breaking` to catch changes that would break consumers.
- **No cross-language shared code.** Keep a small lib per language (`libs/go`, `libs/ts`, `libs/python`) that implements the same conventions: an `outbox` table, a `processed_events` table and one envelope shape. Push as much cross-cutting work as possible into infra: APISIX for JWT, the OTel Collector, and broker-level dedupe.
- **Layout:** `contracts/`, `services/<svc>/`, `libs/<lang>/`, `tests/` (black-box), `deploy/{compose,k8s}`, `docs/`. Keep Vagrant and Ansible at the root.
- **Native tooling per language:** `go.work`, a pnpm workspace and a uv workspace. No Nx or Bazel.
- **CI:** path filters per service, and a change under `contracts/**` rebuilds everything. Shared scanners are Semgrep, gitleaks, Trivy, Syft, cosign and SonarQube. Per-language scanners are gosec/govulncheck, pnpm audit and bandit/pip-audit.
- **mise:**
  - A root `mise.toml` declares go, node, python, pnpm, uv, buf, `pipx:ansible-core`, kubectl, helm, k6, trivy, gitleaks, syft and cosign.
  - A per-service `mise.toml` overrides versions where needed. For Partner API, set `_.python.venv` there.
  - Use mise tasks instead of a Taskfile, with monorepo tasks via `experimental_monorepo_root`.
  - Other pieces: `mise trust`, `mise.lock` with `lockfile = true`, `mise.local.toml` added to `.gitignore`, and `jdx/mise-action` in CI.
  - Dockerfile base images still need to be pinned by hand to match.
  - The version numbers I gave were only examples. **Check them against `mise ls-remote` and the mise docs before writing them down.** In particular, the experimental settings and monorepo-tasks syntax may have changed.

## Open questions the user deferred (don't push; let them raise it)

1. Which language for the GraphQL BFF? I suggested Node, alongside Event Catalog.
2. Should event schemas be protobuf (my recommendation) or JSON Schema with AsyncAPI?
3. Which message broker: NATS JetStream, Kafka or RabbitMQ? It needs good clients in all 3 languages.
4. `tech_stack_summary.html` needs updating for the TicketLite domain and the polyglot stack.
5. Earlier I suggested moving the docs into `docs/`. It's not confirmed.

## Likely next steps (only when the user asks)

- Answer more design questions, or write down the decisions (an ADR) once the user settles the open questions.
- Scaffold the monorepo: `mise.toml`, `contracts/`, the service folders and the `.gitignore` additions.
- Update `tech_stack_summary.html` and the README.

## Suggested skills

- `engineering:architecture` to write ADRs for the polyglot monorepo, the event schema format and the broker choice once the user decides.
- `engineering:system-design` for further service-boundary and contract discussion.
- `engineering:testing-strategy` to turn the doc's test list (race on hold, late payment, duplicate events, webhook replay, IDOR, double scan) into a plan.
- `artifact-design` if updating or regenerating the HTML docs (`tech_stack_summary.html`) as a published page.
- `update-config` only if the user wants Claude Code permissions or hooks for mise and buf commands. That is not mise config itself.
