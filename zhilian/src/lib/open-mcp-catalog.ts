import type { LocaleKey } from "@/locales";

/** Open-source MCP servers that run with `npx` and do not need an API key. */
export interface OpenMcpPreset {
  id: string;
  packageName: string;
  blurbKey: LocaleKey;
}

export const OPEN_MCP_PRESETS: readonly OpenMcpPreset[] = [
  { id: "memory", packageName: "@modelcontextprotocol/server-memory", blurbKey: "mcp.preset.memory" },
  { id: "thinking", packageName: "@modelcontextprotocol/server-sequential-thinking", blurbKey: "mcp.preset.thinking" },
  { id: "playwright", packageName: "@playwright/mcp", blurbKey: "mcp.preset.playwright" },
  { id: "files", packageName: "@modelcontextprotocol/server-filesystem", blurbKey: "mcp.preset.files" },
];

export function openMcpArgs(preset: OpenMcpPreset, directory?: string): string[] {
  const args = ["-y", preset.packageName];
  if (preset.id === "files") args.push(directory || ".");
  return args;
}
