// SPDX-License-Identifier: GPL-3.0-only
// A pi extension that `cachyos-agent launch --local` loads with
// `pi --extension`. It registers the local Ollama server as the "ollama"
// provider for that run only, so ~/.pi/agent/models.json stays untouched.
// The launcher sets CACHYOS_AGENT_LOCAL_MODEL, CACHYOS_AGENT_LOCAL_URL and
// CACHYOS_AGENT_LOCAL_CTX, the tokens of context the model runs with.
// Pi loads extensions through jiti, so no build step is needed
// (https://github.com/earendil-works/pi, docs/custom-provider.md).
export default function (pi) {
  const model = process.env.CACHYOS_AGENT_LOCAL_MODEL;
  const baseUrl = process.env.CACHYOS_AGENT_LOCAL_URL;
  if (!model || !baseUrl) return;
  // Ollama silently truncates every prompt past the context it loaded the model
  // with, so pi must plan for that window and no more: without a number it
  // assumes 4096, the least Ollama defaults to.
  const context = Number.parseInt(process.env.CACHYOS_AGENT_LOCAL_CTX ?? "", 10) || 4096;

  pi.registerProvider("ollama", {
    name: "Ollama (local)",
    baseUrl,
    // Ollama ignores the key, pi wants one before it offers the model.
    apiKey: "ollama",
    api: "openai-completions",
    models: [
      {
        type: "chat",
        id: model,
        name: model,
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: context,
        // A quarter of the window at most, so the answer leaves room for the prompt.
        maxTokens: Math.min(8192, Math.floor(context / 4)),
      },
    ],
  });
}
