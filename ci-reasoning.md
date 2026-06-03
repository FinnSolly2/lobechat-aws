# CI reasoning for `lobechat-aws`

![GitHub Actions run evidence](docs/evidence/ci/actions-run.png)

- **Actions run URL:** `TO_FILL_AFTER_PUSH`
- **Commit SHA executed by that run:** `TO_FILL_AFTER_PUSH`

## Part A - Why what I did matters (repository-specific)

This repository currently has no CI, so I added a build-free static pipeline that catches issues without running the 11-service stack.

1. **Hadolint on both Dockerfiles** catches risky image and Dockerfile practices in this exact repo:
   - `dockerfiles/mcphub.Dockerfile:1` uses `FROM samanhappy/mcphub:latest` (floating tag; non-reproducible base image).
   - `dockerfiles/mcphub.Dockerfile:5` switches to `USER root` and `dockerfiles/mcphub.Dockerfile:7` installs `docker.io` + `gcc` into runtime.
   - `dockerfiles/sandbox.Dockerfile:25`, `dockerfiles/sandbox.Dockerfile:43`, `dockerfiles/sandbox.Dockerfile:50`, and `dockerfiles/sandbox.Dockerfile:62` download tooling from moving "latest/stable" URLs; `dockerfiles/sandbox.Dockerfile:21` adds NOPASSWD sudo.

2. **Compose validation (`docker compose config -q`)** verifies schema/interpolation for this stack without running containers:
   - `docker-compose.yml:35`, `docker-compose.yml:40`, `docker-compose.yml:41`, `docker-compose.yml:53`, `docker-compose.yml:55`, `docker-compose.yml:97`, and `docker-compose.yml:157` require env interpolation and fail when variables are missing.
   - The CI fix (`cp .env.example .env`) is safe because `.gitignore:8` ignores `.env`; placeholders in `.env.example` are non-production defaults (`.env.example:3`).

3. **YAML lint + actionlint** catches structural mistakes before merge:
   - The stack is fully driven by YAML (`docker-compose.yml`) and workflow logic (`.github/workflows/ci.yml`), so syntax drift can break either local orchestration checks or Actions execution.

4. **Gitleaks** adds repository-level leak detection over history and working tree:
   - It helps detect accidentally committed credentials even though this repo already excludes common secret paths like `.env` (`.gitignore:8`), `aws_credentials.yaml` (`.gitignore:19`), `*.pem` (`.gitignore:20`), and `config/ssh/` (`.gitignore:26`).

5. **Trivy fs + config** catches package and misconfiguration risk relevant to these files:
   - `docker-compose.yml:109` and `docker-compose.yml:185` use `:latest` tags (`qdrant` and `minio`).
   - `docker-compose.yml:21` has an untagged `lobehub/lobe-chat-database` image.
   - `docker-compose.yml:13` uses `sslmode=disable` for Casdoor DB connectivity.
   - `docker-compose.yml:32` database URL for lobe-chat has no TLS parameters.

6. **Commitizen check in CI mirrors existing local policy**
   - Local hook already enforces conventional commits via `.githooks/commit-msg:13` (`uv run cz check --commit-msg-file`).
   - CI mirrors that policy with `uv run cz check --rev-range ...` (bounded to new commits, not whole history).

### Why this CI is build-free, and why tests are excluded

- The stack contains GPU-only workload and slow startup that are not suitable for standard hosted runners: `docker-compose.yml:151` (`vllm` service), GPU reservation in `docker-compose.yml:173`, and health `start_period: 300s` at `docker-compose.yml:182`.
- `tests/` are live integration tests, not offline unit tests. For example `tests/test_vllm.py:9` imports `httpx`, `tests/test_vllm.py:11` imports `openai`, and `tests/test_vllm.py:33` calls a live `/health` endpoint.

## Part B - What is still missing for real production CI/CD

What I built is **Continuous Integration** only (static quality/security checks). It does **not** yet implement Continuous Delivery/Deployment for this system.

To reach production-grade CD for this repository, at least the following are still needed:

1. **Deterministic image supply chain**
   - Build/push/sign/SBOM for locally built images from `dockerfiles/mcphub.Dockerfile` and `dockerfiles/sandbox.Dockerfile`.
   - Replace floating images in `docker-compose.yml:109`, `docker-compose.yml:185`, and untagged `docker-compose.yml:21` with immutable digests.

2. **OIDC-based AWS federation for CI credentials**
   - Current runtime pattern mounts host credentials (`docker-compose.yml:103`).
   - `.env.example:61`-`.env.example:63` shows static AWS key placeholders, which should be replaced by short-lived federated credentials in CI.

3. **Secret manager injection at deploy time**
   - Compose currently injects sensitive env vars directly (`docker-compose.yml:35`, `docker-compose.yml:41`, `docker-compose.yml:53`, `docker-compose.yml:55`, `docker-compose.yml:157`).
   - Production deployment should inject these from AWS SSM/Secrets Manager per environment instead of storing values in CI.

4. **Migration stage with guard rails**
   - This repo has a migration pipeline in `db/flyway/provision.sh`.
   - Destructive operation exists at `db/flyway/provision.sh:68`-`db/flyway/provision.sh:72` (`clean` path), so production CD needs approval gates and safer migration promotion rules.

5. **Environment promotion flow + approvals**
   - Add explicit dev -> stage -> prod promotion with protected environments and manual approvals; current repo has no deployment workflow or environment separation encoded in `.github/workflows/`.

6. **Deployment + post-deploy verification + rollback**
   - Add a deploy job for target hosts plus smoke tests/health checks after deploy.
   - Some services already declare health checks (`docker-compose.yml:117`, `docker-compose.yml:177`, `docker-compose.yml:198`, `docker-compose.yml:229`) but others do not, so production gates need consistent health validation.
   - Rollback should be deterministic; currently runtime behavior depends on a mounted hotfix file (`docker-compose.yml:27`) instead of a baked, versioned image artifact.

### Highest-value next step

The single highest-value next step is to implement deterministic image build-and-release (build, sign, SBOM, push to registry, deploy by immutable digest). This directly removes the largest reproducibility and rollback risk created by floating/untagged image references in `docker-compose.yml` and `dockerfiles/mcphub.Dockerfile`. Once artifact immutability is in place, promotion, rollback, and auditability become reliable foundations for the rest of CD.
