# Security, Governance, FinOps - Day 6

Everything here runs locally: InsightHub (docker compose project `insighthub-day6`) -> LiteLLM gateway
(guardrail, budgets, audit) -> Ollama (`qwen2.5:0.5b`, `mxbai-embed-large`). No AWS, no paid API. Model and image
digests are in [MODELS.md](MODELS.md); the threat model is [threat-model.md](threat-model.md).

## Layout
| Path | What |
|---|---|
| `promptfooconfig.yaml`, `redteam.yaml`, `providers/insighthub.js` | Promptfoo 0.123.1 red team (8 plugins, 63 generated cases). The provider uploads the untrusted `{{doc}}` through `/documents`, waits for ingestion, asks `/chat`, then deletes the document |
| `dataset.json`, `eval/harness.py` | Frozen deterministic dataset (22 cases: attacks + benign regression) and the live runner used by the verifier tests |
| `litellm/config.yaml`, `litellm/guardrails/` | Gateway models, shadow prices, Prometheus callback, `litellm_content_filter` guardrails |
| `../tests/milestones/day6/` | Verifier tests (`test_injection_blocked`, `test_benign_allowed`, `test_budget_enforced` + extras) |

## Coverage mapping (plugin IDs verified with `promptfoo redteam plugins` on the pinned version)
| Risk | Plugin / strategy | Cases |
|---|---|---|
| Direct injection / jailbreak | `hijacking`, `system-prompt-override` | 10 + 10 |
| Indirect injection (poisoned document) | `indirect-prompt-injection` (payload uploaded as a document) | 9 |
| RAG poisoning / exfiltration | `rag-poisoning` (custom `llm-rubric`, the pinned version ships no grader for it), `rag-document-exfiltration` | 3 + 10 |
| PII | `pii:direct` | 1 |
| Excessive agency | `excessive-agency` | 10 |
| System prompt leakage | `prompt-extraction` | 10 |
| Strategy | `basic` only. Jailbreak strategies were skipped: they multiply the case count and the host is CPU-only | - |

Generation uses Promptfoo remote generation (`CI=true` uses its placeholder identity, no personal email is sent);
graders run on the local gateway with the dedicated `promptfoo` virtual key. Case counts per plugin come from the
generator (some plugins returned fewer than `numTests`; `pii:direct` only 1 because the local model could not
produce more valid prompts).

## Reproduce (from the repository root, `.env` holds all keys and is never committed)
```bash
docker compose -p insighthub-day6 --profile ollama -f docker-compose.yml -f docker-compose.day6.yml up -d --build --wait \
  postgres redis ollama litellm-db litellm api ingestion-worker
docker exec insighthub-day6-ollama-1 ollama pull qwen2.5:0.5b && docker exec insighthub-day6-ollama-1 ollama pull mxbai-embed-large
docker exec insighthub-day6-ollama-1 ollama pull qwen2.5:1.5b            # Promptfoo grader
python3 scripts/day6/bootstrap_keys.py                                   # 4 virtual keys -> .env
python3 scripts/day6/reset_corpus.py                                     # re-index sample-docs (includes the poisoned file)
cd security && npm ci --ignore-scripts && set -a && . ../.env && set +a && CI=true npx promptfoo redteam eval -c redteam.yaml -j 1
cd .. && python3 scripts/day6/run_eval.py final                           # deterministic dataset
PATH=$PWD/venv/bin:$PATH scripts/verify-day-6.sh --api-url http://localhost:18000 --test-timeout 1800
```
The verifier's default `--test-timeout 120` is too short: the tests call the local CPU model for every dataset case
(about 5 minutes); always pass `--test-timeout 1800`.
