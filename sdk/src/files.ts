import fs from "node:fs";
import path from "node:path";
import type { Address, PublicClient, Chain, Transport } from "viem";
import { MEMONEX_IMPRINTS_ABI } from "./abi.js";
import {
  getWorkspacePath,
  getImprintsHome,
  getImprintsMemoryDir,
  getActiveImprintsPath,
  getImprintsStatePath,
  getLibraryDir,
  getSlotDir,
  getMemoryMdPath,
  getDailyNotePath,
} from "./paths.js";
import type { CanonicalImprint, EquipSlot, ImprintsState, WatermarkReceipt } from "./types.js";

const MAX_SLOTS = 5;

function ensureDir(dir: string): void {
  fs.mkdirSync(dir, { recursive: true });
}

// ── Directory management ────────────────────────────────────────

/**
 * Create all required directories for the imprints system.
 * Works for any agent — paths are resolved from env vars / auto-detection.
 */
export function ensureImprintDirs(): void {
  ensureDir(getImprintsMemoryDir());
  ensureDir(path.join(getImprintsMemoryDir(), "archive"));
  ensureDir(getLibraryDir());
  for (let i = 1; i <= MAX_SLOTS; i++) {
    ensureDir(getSlotDir(i));
  }
}

// ── Slot operations ─────────────────────────────────────────────

export function saveImprintToSlot(
  slot: number,
  imprint: CanonicalImprint,
  receipt: WatermarkReceipt,
): void {
  if (slot < 1 || slot > MAX_SLOTS) throw new Error(`Slot must be 1-${MAX_SLOTS}`);
  const dir = getSlotDir(slot);
  ensureDir(dir);

  // Atomic write via temp file + rename
  const imprintPath = path.join(dir, "imprint.canonical.json");
  const receiptPath = path.join(dir, "receipt.watermark.json");
  const tmpImprint = `${imprintPath}.tmp`;
  const tmpReceipt = `${receiptPath}.tmp`;

  fs.writeFileSync(tmpImprint, JSON.stringify(imprint, null, 2));
  fs.renameSync(tmpImprint, imprintPath);

  fs.writeFileSync(tmpReceipt, JSON.stringify(receipt, null, 2));
  fs.renameSync(tmpReceipt, receiptPath);
}

export function removeImprintFromSlot(slot: number): void {
  if (slot < 1 || slot > MAX_SLOTS) throw new Error(`Slot must be 1-${MAX_SLOTS}`);
  const dir = getSlotDir(slot);
  fs.rmSync(path.join(dir, "imprint.canonical.json"), { force: true });
  fs.rmSync(path.join(dir, "receipt.watermark.json"), { force: true });
}

// ── Library ─────────────────────────────────────────────────────

export function saveToLibrary(
  tokenId: number,
  imprint: CanonicalImprint,
  receipt: WatermarkReceipt,
): void {
  const dir = path.join(getLibraryDir(), `token-${tokenId}`);
  ensureDir(dir);
  fs.writeFileSync(path.join(dir, "imprint.canonical.json"), JSON.stringify(imprint, null, 2));
  fs.writeFileSync(path.join(dir, "receipt.watermark.json"), JSON.stringify(receipt, null, 2));
}

// ── State persistence ───────────────────────────────────────────

export function readImprintsState(): ImprintsState | null {
  const statePath = getImprintsStatePath();
  if (!fs.existsSync(statePath)) return null;
  return JSON.parse(fs.readFileSync(statePath, "utf-8"));
}

export function writeImprintsState(state: ImprintsState): void {
  const statePath = getImprintsStatePath();
  ensureDir(path.dirname(statePath));
  fs.writeFileSync(statePath, JSON.stringify(state, null, 2));
}

// ── Read equipped slots ─────────────────────────────────────────

export function readEquippedSlots(): (EquipSlot | null)[] {
  const slots: (EquipSlot | null)[] = [];
  for (let i = 1; i <= MAX_SLOTS; i++) {
    const dir = getSlotDir(i);
    const imprintFile = path.join(dir, "imprint.canonical.json");
    const receiptFile = path.join(dir, "receipt.watermark.json");

    if (fs.existsSync(imprintFile) && fs.existsSync(receiptFile)) {
      const imprint: CanonicalImprint = JSON.parse(fs.readFileSync(imprintFile, "utf-8"));
      const receipt: WatermarkReceipt = JSON.parse(fs.readFileSync(receiptFile, "utf-8"));
      slots.push({
        slotNumber: i,
        tokenId: receipt.tokenId,
        imprint,
        receipt,
        equippedAt: receipt.deliveredAt,
      });
    } else {
      slots.push(null);
    }
  }
  return slots;
}

// ── ACTIVE-IMPRINTS.md generation ───────────────────────────────

/**
 * Generate and write ACTIVE-IMPRINTS.md to the agent's memory tree.
 * Path: $WORKSPACE/memory/memonex/ACTIVE-IMPRINTS.md
 */
export function generateAndWriteActiveImprints(
  slots: (EquipSlot | null)[],
  contractAddress?: Address,
  lastVerified?: string,
): string {
  const content = generateActiveImprintsMd(slots, contractAddress, lastVerified);
  const filePath = getActiveImprintsPath();
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, content);
  return filePath;
}

export function generateActiveImprintsMd(
  slots: (EquipSlot | null)[],
  contractAddress?: Address,
  lastVerified?: string,
): string {
  const lines: string[] = [
    "# Active Imprints",
    "",
    "> Imprints currently influencing personality. Max 5 slots.",
    "> Auto-generated — do not edit manually.",
    "",
    "## Equipped",
  ];

  const equipped: EquipSlot[] = [];
  for (let i = 0; i < MAX_SLOTS; i++) {
    const slot = slots[i] ?? null;
    if (slot) {
      const verified = slot.receipt.contentHashVerified ? "verified" : "unverified";
      const rarity = slot.imprint.rarity.charAt(0).toUpperCase() + slot.imprint.rarity.slice(1);
      lines.push(`- **Slot ${i + 1}**: ${slot.imprint.name} (${rarity}) — Licensed (${verified})`);
      equipped.push(slot);
    } else {
      lines.push(`- Slot ${i + 1}: Empty`);
    }
  }

  if (equipped.length > 0) {
    lines.push("", "## Personality Rules (apply on top of SOUL.md)");
    const tones = equipped.map((s) => s.imprint.personality.tone).filter(Boolean);
    if (tones.length > 0) {
      lines.push(`- Tone: ${tones.join(", with ")}`);
    }
    for (const slot of equipped) {
      for (const rule of slot.imprint.personality.rules) {
        lines.push(`- ${rule}`);
      }
    }

    const catchphrases = equipped.flatMap((s) => s.imprint.personality.catchphrases);
    if (catchphrases.length > 0) {
      lines.push("", "## Catchphrases");
      for (const c of catchphrases) {
        lines.push(`- "${c}"`);
      }
    }

    const restrictions = equipped.flatMap((s) => s.imprint.personality.restrictions);
    if (restrictions.length > 0) {
      lines.push("", "## Effective Restrictions");
      for (const r of restrictions) {
        lines.push(`- ${r}`);
      }
    }
  }

  lines.push("", "## Provenance");
  lines.push(`- Last verified: ${lastVerified ?? new Date().toISOString()}`);
  if (contractAddress) {
    lines.push(`- Contract: ${contractAddress} (Monad testnet)`);
  }
  lines.push("");

  return lines.join("\n");
}

// ── Ownership check ─────────────────────────────────────────────

export async function checkOwnershipForAll(
  publicClient: PublicClient<Transport, Chain>,
  contractAddress: Address,
  wallet: Address,
  slots: (EquipSlot | null)[],
): Promise<{ slot: number; tokenId: number; owned: boolean }[]> {
  const results: { slot: number; tokenId: number; owned: boolean }[] = [];

  for (const slot of slots) {
    if (!slot) continue;
    const balance = (await publicClient.readContract({
      address: contractAddress,
      abi: MEMONEX_IMPRINTS_ABI,
      functionName: "balanceOf",
      args: [wallet, BigInt(slot.tokenId)],
    })) as bigint;

    results.push({
      slot: slot.slotNumber,
      tokenId: slot.tokenId,
      owned: balance > 0n,
    });
  }

  return results;
}

// ── AGENTS.md hook ─────────────────────────────────────────────

const AGENTS_HOOK_MARKER = "## Memonex — Purchased Knowledge & Imprints";

const AGENTS_HOOK_CONTENT = `
## Memonex — Purchased Knowledge & Imprints
After each session start, check these files for purchased knowledge:
- Read \`memory/memonex/ACTIVE-IMPRINTS.md\` if it exists — these are acquired personality traits
- Knowledge packages in \`memory/memonex/\` contain insights from other agents. Key summaries are in MEMORY.md.
`;

/**
 * Append the imprints hook to AGENTS.md if not already present.
 * Idempotent — safe to call multiple times.
 * Returns true if the hook was added, false if it already existed or AGENTS.md doesn't exist.
 */
export function ensureAgentsHook(): boolean {
  const agentsPath = path.join(getWorkspacePath(), "AGENTS.md");
  if (!fs.existsSync(agentsPath)) return false;

  const content = fs.readFileSync(agentsPath, "utf-8");
  if (content.includes(AGENTS_HOOK_MARKER)) return false;

  fs.appendFileSync(agentsPath, AGENTS_HOOK_CONTENT);
  return true;
}

// ── Resolved paths (for debugging / SKILL.md scripts) ───────────

export function getResolvedPaths(): Record<string, string> {
  return {
    OPENCLAW_ROOT: path.dirname(getWorkspacePath()),
    WORKSPACE: getWorkspacePath(),
    IMPRINTS_HOME: getImprintsHome(),
    IMPRINTS_MEMORY_DIR: getImprintsMemoryDir(),
    ACTIVE_IMPRINTS_MD: getActiveImprintsPath(),
    STATE_JSON: getImprintsStatePath(),
    LIBRARY: getLibraryDir(),
    MEMORY_MD: getMemoryMdPath(),
  };
}
