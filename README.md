# LobeChat AWS Stack

Self-hosted LobeChat AI chat platform, deployed on a single AWS EC2 instance behind
an HTTPS reverse proxy. Bundles PostgreSQL (pgvector), Casdoor SSO, MinIO object
storage, a vLLM inference service, and MCPHub routing seven MCP tool servers.

Built for the ESADE DevOps final project — see [`docs/FINAL-PROJECT.md`](docs/FINAL-PROJECT.md)
for the brief and [`docs/evidence/REPORT.md`](docs/evidence/REPORT.md) for the deployment evidence.

## Architecture

```
                         Internet (HTTPS / 443)
                                  |
                         Caddy reverse proxy
                  (Let's Encrypt cert, DuckDNS host)
                                  |
        +-------------------------+-------------------------+
        |                         |                         |
   LobeChat (:47000)        Casdoor (:47002)          MinIO (:47005)
        |                         |                         |
        +--> Casdoor (auth)       +--> PostgreSQL (casdoor db)
        +--> PostgreSQL (lobechat db, pgvector)
        +--> MinIO (file storage)
        +--> MCPHub (:47008) --> 7 MCP servers (ssh-exec, aws-*, playwright,
        |                         minio, notion, filesystem)
        +--> vLLM (:47007) / OpenRouter (inference + embeddings)
```

Direct access to application ports is blocked at the EC2 security group; the stack is
reachable **only** over HTTPS through Caddy.

## Services

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| LobeChat | lobe-chat | 47000 | Main chat application (Next.js, DB backend) |
| Casdoor | casdoor | 47002 | SSO / OAuth authentication provider |
| MCPHub | mcphub | 47008 | Routes to 7 MCP tool servers |
| vLLM | vllm | 47007 | Local LLM inference (mock on CPU-only hosts) |
| MinIO API | minio | 47005 | S3-compatible object storage |
| MinIO Console | minio | 47006 | Storage admin UI |
| PostgreSQL | shared-postgres | 47003 | pgvector database (lobechat + casdoor DBs) |

## Quick start (local)

```bash
cp .env.example .env          # then fill in the secrets (see below)
docker compose up -d          # start the stack
docker compose logs -f lobe-chat
docker compose down           # stop
```

Minimum secrets in `.env`: `KEY_VAULTS_SECRET` and `NEXT_AUTH_SECRET` (≥32 chars each),
`OPENROUTER_API_KEY` for inference/embeddings, plus the Postgres/MinIO/Casdoor/MCPHub
credentials referenced in `.env.example`. No secrets are committed to git — the
`config/*.json` files are templates (`*.tpl`) rendered at bootstrap.

## Deploy on AWS EC2

1. Launch an Ubuntu 24.04 LTS instance in `eu-west-1` (≥ 4 vCPU / 16 GB RAM / 60 GB gp3),
   open only ports 22, 80, and 443 in the security group.
2. Point a hostname at the instance (e.g. DuckDNS subdomain) so a public CA can issue a
   TLS certificate.
3. SSH in, export the required secrets (see the header of `bootstrap-lobechat.sh`), then run:

   ```bash
   ./bootstrap-lobechat.sh
   ```

   The script is idempotent: it installs Docker + Caddy, clones the repo, renders the
   config templates from environment variables, writes a `chmod 600` `.env`, configures
   Caddy (HTTPS via Let's Encrypt), and brings the stack up.
4. Visit `https://<your-host>` once DNS resolves.

`docker-compose.override.yml` replaces the GPU vLLM service with a CPU-only mock for
hosts without an NVIDIA GPU; the LLM backend can also be any OpenAI-compatible endpoint
(OpenRouter, Bedrock, etc.) configured in `.env`.

## Repository layout

```
.
├── docker-compose.yml          # Stack definition
├── docker-compose.override.yml # CPU-only vLLM mock
├── bootstrap-lobechat.sh       # EC2 provisioning script (idempotent)
├── config/
│   ├── *.json.tpl              # Templated configs (rendered at bootstrap)
│   ├── init-postgres.sql       # Creates lobechat + casdoor databases
│   └── casdoor-app.conf        # Casdoor server config
├── db/                         # dbmate migrations, schema.sql, seed.sql
├── patches/route.js            # LobeChat MCP session-retry hotfix
├── tests/                      # pytest suite (vLLM + MCP server checks)
└── docs/
    ├── FINAL-PROJECT.md        # Project brief
    └── evidence/               # REPORT.md, TLS validation, Q1–Q4 answers
```

## Commands

```bash
docker compose up -d                 # Start
docker compose down                  # Stop
docker compose logs -f lobe-chat     # Tail LobeChat logs
docker compose restart <service>     # Restart one service
uv run --group test pytest tests/ -v # Run the test suite
```

See [`CLAUDE.md`](CLAUDE.md) for full command reference (migrations, versioning, etc.).
