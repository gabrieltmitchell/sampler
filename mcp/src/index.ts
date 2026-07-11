#!/usr/bin/env node

import { Command } from "commander";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { AnnotationHub, startHttpServer } from "./http.js";
import { startMcpServer } from "./mcp.js";
import { SamplerStore } from "./store.js";

const program = new Command();

program
  .name("sampler-mcp")
  .description("MCP server for Sampler iOS visual feedback annotations")
  .version("0.1.0");

program
  .command("server")
  .description("Start the Sampler HTTP receiver and MCP stdio server")
  .option("-p, --port <port>", "HTTP server port", "4747")
  .option("--host <host>", "HTTP server host", "127.0.0.1")
  .option("--store <path>", "Storage directory")
  .option("--mcp-only", "Skip the HTTP receiver and only start MCP stdio")
  .action(async (options: { port: string; host: string; store?: string; mcpOnly?: boolean }) => {
    const store = new SamplerStore(options.store);
    const hub = new AnnotationHub();

    if (!options.mcpOnly) {
      const http = await startHttpServer({
        port: Number.parseInt(options.port, 10),
        host: options.host,
        store,
        hub
      });
      console.error(`Sampler HTTP server listening at ${http.url}`);
      console.error(`Sampler store: ${store.rootDir}`);
    }

    await startMcpServer(store, hub);
  });

program
  .command("doctor")
  .description("Check the Sampler MCP local setup")
  .option("--store <path>", "Storage directory")
  .action((options: { store?: string }) => {
    const store = new SamplerStore(options.store);
    const dbPath = join(store.rootDir, "store.db");

    console.log("Sampler MCP doctor");
    console.log(`store: ${store.rootDir}`);
    console.log(`database: ${existsSync(dbPath) ? "ok" : "missing"}`);
    console.log(`sessions: ${store.listSessions().length}`);
    console.log(`pending annotations: ${store.getPending().length}`);
    console.log("");
    console.log("To configure an MCP-aware coding agent:");
    console.log('npx add-mcp "npx -y sampler-mcp server"');
  });

program.parseAsync(process.argv).catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
