# Day 6 model inventory (recorded 2026-09-30)

Provider: Ollama 0.33.3 (image digest `sha256:32931b46719f673c05fdbaa81ccb26da18ea4a1c57590a754874ab28ba269eb2`), local CPU, no API fee.
Gateway: LiteLLM v1.103.1, image `ghcr.io/berriai/litellm@sha256:df15400b5b80925c45d3fd53f8f7a6c0eaa8a25a86833e1b358002e129018943`.

| Gateway alias | Model | Quantization | Model ID / manifest sha256 |
|---|---|---|---|
| `chat-small` | `qwen2.5:0.5b` (494M params, ctx 32768) | Q4_K_M | `a8b0c5157701`, manifest `a8b0c51577010a279d933d14c2a8ab4b268079d44c5c8830c0a93900f1827c67` |
| (not on the gateway) Promptfoo grader/generator | `qwen2.5:1.5b` (1.5B params) | Q4_K_M | `65ec06548149`, manifest `65ec06548149b04c096a120e4a6da9d4017ea809c91734ea5631e89f96ddc57b`; called directly on `127.0.0.1:11434` |
| `embed-mxbai` | `mxbai-embed-large` (334M params, 1024 dims) | F16 | `468836162de7`, manifest `468836162de7f81e041c43663fedbbba921dcea9b9fefea135685a39b2d83dd8` |

Pricing: Ollama has no provider fee (real cost 0; resource usage is measured). `security/litellm/config.yaml` sets
SHADOW prices (chat 0.15/0.60 USD per 1M in/out, embedding 0.02 USD per 1M) only so LiteLLM `max_budget`,
attribution and the dashboard work; they are assumptions, not a bill.
