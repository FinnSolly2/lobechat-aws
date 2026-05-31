"""
Token counter: mcp_settings.json + lobe-chat env vars (URLs & model config)
Encoder: cl100k_base (GPT-4 / Claude approximate)
"""
import json, pathlib, tiktoken

enc = tiktoken.get_encoding("cl100k_base")

# ── 1. mcp_settings.json ─────────────────────────────────────────────────────
MCP_PATH = pathlib.Path(__file__).parent / "config" / "mcp_settings.json"
mcp_text = MCP_PATH.read_text(encoding="utf-8")
mcp_chars = len(mcp_text)
mcp_tokens = len(enc.encode(mcp_text))

# ── 2. lobe-chat env vars with URL / model config (from docker-compose.yml) ──
# No SYSTEM_PROMPT / DEFAULT_AGENT_CONFIG / CUSTOM_MODEL_LIST found in compose.
# Captured verbatim from the environment: block of the lobe-chat service.
LOBE_ENV_VARS = {
    "APP_URL":             "http://${HOST_DOMAIN:-localhost}:${LOBECHAT_PORT:-47000}",
    "DATABASE_URL":        "postgresql://postgres:${POSTGRES_PASSWORD:-postgres}@postgres:5432/lobechat",
    "NEXTAUTH_URL":        "http://${HOST_DOMAIN:-localhost}:${LOBECHAT_PORT:-47000}",
    "AUTH_URL":            "http://${HOST_DOMAIN:-localhost}:${LOBECHAT_PORT:-47000}",
    "AUTH_CASDOOR_ISSUER": "http://${HOST_DOMAIN:-localhost}:${CASDOOR_PORT:-47002}",
    "S3_ENDPOINT":         "https://${S3_HOST_DOMAIN:-esade-user81-s3.duckdns.org}",
    "S3_PUBLIC_DOMAIN":    "https://${S3_HOST_DOMAIN:-esade-user81-s3.duckdns.org}",
    "OPENAI_PROXY_URL":    "https://openrouter.ai/api/v1",
    "DEFAULT_FILES_CONFIG":"embedding_model=openai/text-embedding-3-small",
    "ENABLED_OPENROUTER":  "1",
    "LLM_VISION_IMAGE_USE_BASE64": "1",
}
# Concatenate as KEY=VALUE pairs (how they appear in a process environment)
env_text = "\n".join(f"{k}={v}" for k, v in LOBE_ENV_VARS.items())
env_chars = len(env_text)
env_tokens = len(enc.encode(env_text))

# ── 3. Default system prompt estimate (not found in env → ~400 tokens) ────────
# LobeChat ships a built-in system prompt; not exposed via env var in this stack.
DEFAULT_SYS_PROMPT_NOTE = "(not set in env — using LobeChat built-in default)"
DEFAULT_SYS_PROMPT_CHARS = 400 * 4   # ~4 chars/token rule-of-thumb for estimate
DEFAULT_SYS_PROMPT_TOKENS = 400       # canonical estimate

# ── 4. Print table ────────────────────────────────────────────────────────────
COL = "{:<42} {:>12} {:>10}"
SEP = "-" * 68
print(SEP)
print(COL.format("component", "characters", "tokens"))
print(SEP)
print(COL.format("config/mcp_settings.json", mcp_chars, mcp_tokens))
print(COL.format("lobe-chat URL/model env vars (11 vars)", env_chars, env_tokens))
print(COL.format("LobeChat default system prompt (est.)", DEFAULT_SYS_PROMPT_CHARS, DEFAULT_SYS_PROMPT_TOKENS))
print(SEP)
total_chars  = mcp_chars  + env_chars  + DEFAULT_SYS_PROMPT_CHARS
total_tokens = mcp_tokens + env_tokens + DEFAULT_SYS_PROMPT_TOKENS
print(COL.format("TOTAL", total_chars, total_tokens))
print(SEP)
print()
print(f"Note: SYSTEM_PROMPT, DEFAULT_AGENT_CONFIG, CUSTOM_MODEL_LIST")
print(f"      are NOT present in docker-compose.yml lobe-chat env block.")
print(f"      {DEFAULT_SYS_PROMPT_NOTE}")
