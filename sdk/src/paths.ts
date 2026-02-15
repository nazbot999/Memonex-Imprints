import fs from "node:fs";
import os from "node:os";
import path from "node:path";

/**
 * Central path resolution for the Memonex Imprints SDK.
 *
 * All paths derive from three roots, each overridable via env var:
 *
 *   OPENCLAW_ROOT           (default: ~/.openclaw)
 *   OPENCLAW_WORKSPACE      (default: <OPENCLAW_ROOT>/workspace)
 *   IMPRINTS_HOME           (default: <OPENCLAW_ROOT>/memonex-imprints)
 *
 * Every function reads env vars at call time (not import time) so that
 * tests and late-binding configs work correctly.
 */

/** Heuristic: does `dir` look like an OpenClaw root directory? */
function looksLikeOpenclawRoot(dir: string): boolean {
  try {
    if (fs.statSync(path.join(dir, "openclaw.json"), { throwIfNoEntry: false })) return true;
    if (fs.statSync(path.join(dir, "workspace"), { throwIfNoEntry: false })?.isDirectory()) return true;
  } catch {
    // fs errors → not a valid root
  }
  return false;
}

export function getOpenclawRoot(): string {
  // 1. Explicit env var (highest priority)
  if (process.env.OPENCLAW_ROOT) return process.env.OPENCLAW_ROOT;

  // 2. Derive from workspace env var
  if (process.env.OPENCLAW_WORKSPACE) return path.dirname(process.env.OPENCLAW_WORKSPACE);

  // 3. Derive from IMPRINTS_HOME (parent dir, validated)
  if (process.env.IMPRINTS_HOME) {
    const candidate = path.dirname(process.env.IMPRINTS_HOME);
    if (looksLikeOpenclawRoot(candidate)) return candidate;
  }

  // 4. Infer from cwd — scripts run via `cd $IMPRINTS_HOME && npx tsx ...`
  const cwdParent = path.dirname(process.cwd());
  if (looksLikeOpenclawRoot(cwdParent)) return cwdParent;

  // 5. Fallback: default location
  return path.join(os.homedir(), ".openclaw");
}

export function getWorkspacePath(): string {
  return process.env.OPENCLAW_WORKSPACE ?? path.join(getOpenclawRoot(), "workspace");
}

export function getImprintsHome(): string {
  return process.env.IMPRINTS_HOME ?? path.join(getOpenclawRoot(), "memonex-imprints");
}

/** Directory where imprint markdown files are stored in the agent's memory tree. */
export function getImprintsMemoryDir(): string {
  return path.join(getWorkspacePath(), "memory", "memonex", "imprints");
}

/** Directory for archived (subtle-strength) imprints. */
export function getImprintsArchiveDir(): string {
  return path.join(getImprintsMemoryDir(), "archive");
}

/** Path to ACTIVE-IMPRINTS.md in the agent's memory. */
export function getActiveImprintsPath(): string {
  return path.join(getWorkspacePath(), "memory", "memonex", "ACTIVE-IMPRINTS.md");
}

/** Path to the imprints state file (equipped slots, wallet, last check). */
export function getImprintsStatePath(): string {
  return path.join(getImprintsHome(), "state.json");
}

/** Path to the imprints library (all owned, including unequipped). */
export function getLibraryDir(): string {
  return path.join(getImprintsHome(), "library");
}

/** Directory for a specific slot's content. */
export function getSlotDir(slot: number): string {
  return path.join(getImprintsHome(), "equipped", `slot-${slot}`);
}

/** Agent's MEMORY.md for purchase summaries. */
export function getMemoryMdPath(): string {
  return path.join(getWorkspacePath(), "MEMORY.md");
}

/** Agent's daily note. */
export function getDailyNotePath(): string {
  const date = new Date().toISOString().slice(0, 10);
  return path.join(getWorkspacePath(), "memory", `${date}.md`);
}
