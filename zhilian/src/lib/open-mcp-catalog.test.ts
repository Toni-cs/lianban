import { describe, expect, it } from "vitest";

import { OPEN_MCP_PRESETS, openMcpArgs } from "./open-mcp-catalog";

describe("open-source MCP presets", () => {
  it("names each server once and points npx at a public package", () => {
    expect(new Set(OPEN_MCP_PRESETS.map((preset) => preset.id)).size).toBe(OPEN_MCP_PRESETS.length);
    for (const preset of OPEN_MCP_PRESETS) {
      expect(preset.id).toMatch(/^[a-z][a-z0-9_-]{0,31}$/);
      expect(openMcpArgs(preset)[0]).toBe("-y");
      expect(openMcpArgs(preset)[1]).toBe(preset.packageName);
    }
  });

  it("gives the filesystem server a directory", () => {
    const files = OPEN_MCP_PRESETS.find((preset) => preset.id === "files")!;
    expect(openMcpArgs(files, "D:\\Bot")).toEqual(["-y", "@modelcontextprotocol/server-filesystem", "D:\\Bot"]);
  });
});
