// SPDX-License-Identifier: GPL-3.0-only
// A pi extension that `cachyos-agent launch --local` loads with
// `pi --extension`. It registers the local Ollama server as the "ollama"
// provider for that run only, so ~/.pi/agent/models.json stays untouched.
// The launcher sets CACHYOS_AGENT_LOCAL_MODEL and CACHYOS_AGENT_LOCAL_URL.
// Pi loads extensions through jiti, so no build step is needed
// (https://github.com/earendil-works/pi, docs/custom-provider.md).
export default function (pi) {
  const model = process.env.CACHYOS_AGENT_LOCAL_MODEL;
  const baseUrl = process.env.CACHYOS_AGENT_LOCAL_URL;
  if (!model || !baseUrl) return;

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
        // Ollama silently truncates past the context it loaded the model with,
        // so claim a modest window rather than pi's 128000 default.
        contextWindow: 32768,
        maxTokens: 8192,
      },
    ],
  });
}
