# Shared plan compiler

`plan-graph.mjs` is an unmodified copy of the dependency-free bundled runtime
from `namarks/dotfiles`, `agents/skills/planning-conventions/scripts/plan-graph.mjs`,
at commit `32de648e6241ddc15b8d101d17fc916a88b2b9a1`.

SHA-256: `94caffd837cedeeed7ca4010b3cc11afdd753b47681e598e8dd64f284838e008`.

Vendoring keeps `npm run plans:check` identical locally and in CI without an
installed agent skill or a network fetch. Update by copying the upstream bundle,
recording its revision/hash here, and comparing its output with the installed
shared skill against this repository. Do not edit the generated bundle here.
