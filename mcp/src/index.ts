#!/usr/bin/env node

import { Command } from "commander";
import { join } from "node:path";
import { SamplerDispatcher } from "./dispatch.js";
import { runDoctor } from "./doctor.js";
import { AnnotationHub, startHttpServer } from "./http.js";
import { startMcpServer } from "./mcp.js";
import { runInit, runUpdate } from "./setup.js";
import { SamplerStore } from "./store.js";
import type { AutoDispatchStatus } from "./types.js";
import { packageVersion } from "./version.js";

const program = new Command();

program
  .name("sampler-mcp")
  .description("MCP server for Sampler iOS visual feedback annotations")
  .version(packageVersion());

program
  .command("server")
  .description("Start the Sampler HTTP receiver and MCP stdio server")
  .option("-p, --port <port>", "HTTP server port", "4747")
  .option("--host <host>", "HTTP server host", "127.0.0.1")
  .option("--store <path>", "Storage directory")
  .option("--project <path>", "Project directory for auto-dispatched Cursor agents", process.cwd())
  .option("--no-dispatch", "Disable automatic cursor-agent dispatch for new annotations")
  .option("--mcp-only", "Skip the HTTP receiver and only start MCP stdio")
  .action(async (options: {
    port: string;
    host: string;
    store?: string;
    project: string;
    dispatch?: boolean;
    mcpOnly?: boolean;
  }) => {
    const store = new SamplerStore(options.store);
    const hub = new AnnotationHub();
    let dispatcher: SamplerDispatcher | undefined;
    const disabledStatus = (): AutoDispatchStatus => ({
      enabled: false,
      state: "disabled",
      healthy: true,
      project: options.project,
      reason: options.dispatch === false ? "auto-dispatch disabled by --no-dispatch" : "auto-dispatch unavailable",
      lastError: null,
      lastLogPath: null,
      lastLogEmpty: null,
      lastOutput: null,
      retryCount: null,
      pid: null,
      command: null,
      activeAnnotationIds: [],
      updatedAt: new Date().toISOString()
    });

    if (!options.mcpOnly) {
      const http = await startHttpServer({
        port: Number.parseInt(options.port, 10),
        host: options.host,
        store,
        hub,
        autoDispatchStatus: () => dispatcher?.status() ?? disabledStatus(),
        retryDispatch: options.dispatch !== false ? () => dispatcher?.retry() : undefined
      });
      console.error(`Sampler HTTP server listening at ${http.url}`);
      console.error(`Sampler store: ${store.rootDir}`);
      if (options.dispatch !== false) {
        dispatcher = new SamplerDispatcher({
          baseUrl: http.url,
          projectPath: options.project,
          store,
          hub
        });
        dispatcher.start();
        const dispatchStatus = dispatcher.status();
        console.error(`Sampler auto-dispatch: ${dispatchStatus.healthy ? "enabled" : `disabled (${dispatchStatus.reason})`}`);
        console.error(`Sampler auto-dispatch project: ${options.project}`);
      } else {
        console.error("Sampler auto-dispatch: disabled by --no-dispatch");
      }
    }

    await startMcpServer(store, hub);
  });

program
  .command("doctor")
  .description("Check the Sampler MCP local setup")
  .option("--store <path>", "Storage directory")
  .option("--project <path>", "Project directory to inspect")
  .option("-p, --port <port>", "HTTP server port to check", "4747")
  .action(async (options: { store?: string; project?: string; port: string }) => {
    const store = new SamplerStore(options.store);
    const dbPath = join(store.rootDir, "store.db");
    await runDoctor({
      store,
      dbPath,
      project: options.project,
      port: Number.parseInt(options.port, 10)
    });
  });

program
  .command("init")
  .description("Write the Cursor MCP config for Sampler in this project")
  .option("--project <path>", "Project directory", process.cwd())
  .option("--global", "Write to ~/.cursor/mcp.json instead of the project's .cursor/mcp.json")
  .action((options: { project: string; global?: boolean }) => {
    runInit(options);
  });

program
  .command("update")
  .description("Check for sampler-mcp and Sampler widget updates and print update steps")
  .option("--project <path>", "Project directory", process.cwd())
  .action((options: { project: string }) => {
    runUpdate(options);
  });

program.parseAsync(process.argv).catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
