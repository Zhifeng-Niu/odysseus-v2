# Odysseus v2

Brain-inspired autonomous agent runtime.

Three-layer architecture: **Rust NIFs** (sparse matrix, pattern matching) → **Elixir/BEAM** (OTP supervisor tree, GenServer actors) → **TypeScript** (LLM SDK, TUI, API).

## Architecture

```
core/                           # Rust NIFs
├── crates/
│   ├── sparse_matrix/          # Connection matrix + activation spreading
│   ├── hippocampus/            # Memory encoding/recall (neuron groups)
│   ├── amygdala/               # Emotional state machine
│   ├── astrocyte/              # LRU cache (emotion-weighted eviction)
│   ├── basal/                  # Motor programs (5-level hierarchy)
│   ├── cerebellum/             # Prediction error + adjustments
│   ├── neurons/                # Sparse associative memory
│   └── signal_types/           # Shared NIF types

neural/                         # Elixir umbrella app
├── apps/
│   ├── odysseus_brain/         # OTP supervisor + HTTP router (Plug)
│   ├── odysseus_white_matter/  # Pub/sub signal routing
│   ├── odysseus_brain/brainstem.ex    # Never-stop loop
│   ├── odysseus_thalamus/      # Signal routing + consciousness gate
│   ├── odysseus_hypothalamus/  # Homeostasis + state machine
│   ├── odysseus_frontal_left/  # Analytical reasoning (LLM bridge)
│   ├── odysseus_frontal_right/ # Creative intuition (LLM bridge)
│   ├── odysseus_occipital/     # Feature extraction
│   ├── odysseus_parietal/      # Attention allocation
│   ├── odysseus_temporal/      # Language understanding
│   ├── odysseus_amygdala/      # Emotional evaluation
│   ├── odysseus_hippocampus/   # Memory encoding/recall
│   ├── odysseus_basal/         # Action selection
│   ├── odysseus_cerebellum/    # Prediction + error correction
│   ├── odysseus_neurons/       # Sparse memory layer
│   ├── odysseus_astrocyte/     # Resource cache
│   └── odysseus_glymphatic/    # Sleep cleanup

app/                            # TypeScript application
├── src/
│   ├── main.ts                 # Entry point (TUI / API mode)
│   ├── llm.ts                  # Config (12 providers, dual-protocol)
│   ├── llm-client.ts           # OpenAI + Anthropic client
│   ├── brain-bridge.ts         # Elixir HTTP API client
│   ├── frontal-orchestrator/   # Dual-brain reasoning + merge
│   ├── cortex-left/            # Analytical LLM reasoning
│   ├── cortex-right/           # Creative LLM reasoning
│   ├── api/server.ts           # Express + WebSocket + SSE
│   ├── tui/app.tsx             # ink TUI
│   └── wizard.tsx              # Interactive config wizard
```

## Signal Pathway

```
User → TUI → brain-bridge → Elixir /chat → Brainstem → White Matter → Thalamus
  → Occipital (encode) → Parietal (attention) → Temporal (recall cues)
  → FrontalLeft (LLM analysis) + FrontalRight (LLM creative)
  → Basal Ganglia (action select) → Cerebellum (predict)
  → error feedback → Frontal re-plan
```

## Quick Start

```bash
# 1. Install Rust, Elixir, Node.js

# 2. Start everything
./start.sh

# Or run TUI standalone (brain runs at localhost:4001)
cd app && npm install && npx tsx src/main.ts

# API server mode
cd app && npx tsx src/main.ts --api --port 3100
```

## Build

```bash
# Rust NIFs
cd core && cargo build --release

# Elixir
cd neural && mix deps.get && mix compile

# TypeScript
cd app && npm install && npx tsc --noEmit
```

## Environment

| Variable | Purpose | Default |
|----------|---------|---------|
| `ODY_API_KEY` | LLM API key | required |
| `ODY_PROVIDER` | Provider (openai/anthropic/openrouter/gemini/...) | openai |
| `ODY_MODEL` | Model override | provider default |
| `ODYSSEUS_BRAIN_URL` | Elixir brain URL | http://localhost:4001 |

## License

MIT
