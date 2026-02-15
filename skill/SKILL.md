---
name: imprints
description: "Equippable personality NFTs for AI agents. Buy, equip, trade, and transfer imprints on Monad with USDC."
version: 1.1.0
license: MIT
metadata: {"openclaw":{"emoji":"🎭","requires":{"bins":["node","npm"],"env":["IMPRINTS_PRIVATE_KEY"]}}}
---

# Memonex Imprints

Imprints are NFT-backed personality modules (ERC-1155) on Monad, purchasable with USDC. Agents equip imprints to 5 personality slots — the SDK generates `ACTIVE-IMPRINTS.md` which layers personality rules on top of `SOUL.md`. Ownership is verified on-chain; content is delivered via authenticated API.

## Paths

All paths are resolved from environment variables with auto-detection fallbacks.

| Variable | Resolves To | Description |
|----------|-------------|-------------|
| `$OPENCLAW_ROOT` | `~/.openclaw` | OpenClaw installation root |
| `$IMPRINTS_HOME` | `$OPENCLAW_ROOT/memonex-imprints` | Imprints SDK + state root |
| `$WORKSPACE` | `$OPENCLAW_ROOT/workspace` | Agent workspace |
| `$IMPRINTS_SDK` | `$IMPRINTS_HOME/sdk` | SDK directory (run scripts from here) |
| `$LIBRARY` | `$IMPRINTS_HOME/library` | All owned imprints (token-N dirs) |
| `$EQUIPPED` | `$IMPRINTS_HOME/equipped` | Slot dirs (slot-1 through slot-5) |
| `$STATE_JSON` | `$IMPRINTS_HOME/state.json` | Persisted equip state |
| `$ACTIVE_IMPRINTS_MD` | `$WORKSPACE/memory/memonex/ACTIVE-IMPRINTS.md` | Generated personality overlay |
| `$MEMORY_DIR` | `$WORKSPACE/memory/memonex/imprints` | Imprint markdown files |
| `$DAILY_NOTE` | `$WORKSPACE/memory/YYYY-MM-DD.md` | Today's daily note |

## How to Run TypeScript

All code blocks in this file should be:
1. Saved as a `.ts` file in `$IMPRINTS_SDK` (e.g., `_run.ts`)
2. Executed with `npx tsx _run.ts` from the `$IMPRINTS_SDK` directory

Every script starts with this boilerplate:

```typescript
import dotenv from "dotenv";
dotenv.config();
import { createClientsFromEnv, /* ...other imports */ } from "./src/index.js";
const clients = createClientsFromEnv();
```

Key rules:
- All imports from `"./src/index.js"` — never from individual module files
- `parseUsdc()` takes a **string**: `parseUsdc("5")`
- `formatUsdc()` takes a **bigint**: `formatUsdc(balance)`
- Output results as `console.log(JSON.stringify({...}))` for machine parsing
- User-supplied values use `REPLACE_WITH_*` placeholders
- Guard clauses use `process.exit(1)` with descriptive error JSON

## Network Configuration

| Network | Chain ID | Contract | USDC | Gas | Explorer |
|---------|----------|----------|------|-----|----------|
| Monad Testnet | 10143 | `0xe7D1848f413B6396776d80D706EdB02BFc7fefC2` | `0x534b2f3A21130d7a60830c2Df862319e593943A3` | MON | `https://testnet.monadscan.com` |
| Monad | 143 | TBD | `0x754704Bc059F8C67012fEd69BC8A327a5aafb603` | MON | `https://monadscan.com` |

ERC-8004 Registries:

| Network | Identity | Reputation |
|---------|----------|------------|
| Monad Testnet | `0x8004A818BFB912233c491871b3d84c89A494BD9e` | `0x8004B663056A597Dffe9eCcC1965A193B7388713` |
| Monad | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` | `0x8004BAa17C55a88189AE136b182e5fdA19dE9b63` |

## Commands

| Command | Description |
|---------|-------------|
| `/imprints setup` | One-time init: .env, npm install, verify connection, ERC-8004 identity |
| `/imprints browse` | List all imprint types with prices, supply, images |
| `/imprints collections` | Browse active blind-mint collections with pricing, remaining mints, and rarity weighting |
| `/imprints mint-collection <collectionId> [slot]` | Blind mint from a collection, reveal token, claim content, equip, and sync ERC-8004 |
| `/imprints buy <tokenId>` | Full autonomous purchase: USDC approve → buy → claim → equip → sync |
| `/imprints claim <tokenId>` | Claim content for already-owned tokens |
| `/imprints equip <tokenId> [slot]` | Equip from library to slot, regenerate ACTIVE-IMPRINTS.md |
| `/imprints unequip <slot>` | Remove from slot, regenerate, sync ERC-8004 |
| `/imprints sell <tokenId> <price> [expiry]` | List for secondary sale (escrow) |
| `/imprints cancel <tokenId>` | Cancel secondary listing |
| `/imprints transfer <tokenId> <to> [amount]` | Transfer NFT to another wallet |
| `/imprints status` | Equipped slots, library, USDC balance, listings, agentId |
| `/imprints verify` | Batch ownership check, auto-unequip lost, regenerate |

---

## `/imprints setup`

One-time initialization. Creates `.env`, installs dependencies, verifies on-chain connection, checks ERC-8004 identity.

### Step 1: Ask for network and private key

Ask the user:
- Network: `monad-testnet` (recommended) or `monad`
- Private key (must have MON for gas + USDC for purchases)
- API URL (default: `https://memonex-imprints-api.memonex.workers.dev`)

### Step 2: Write .env file

Write to `$IMPRINTS_SDK/.env`:

```
IMPRINTS_PRIVATE_KEY=0x...
IMPRINTS_NETWORK=monad-testnet
IMPRINTS_CONTRACT_ADDRESS=0xe7D1848f413B6396776d80D706EdB02BFc7fefC2
USDC_ADDRESS=0x534b2f3A21130d7a60830c2Df862319e593943A3
IMPRINTS_API_URL=https://memonex-imprints-api.memonex.workers.dev
MONAD_RPC_URL=https://testnet-rpc.monad.xyz
```

### Step 3: Install dependencies

```bash
cd $IMPRINTS_SDK && npm install
```

### Step 4: Verify connection and create directories

Save and run from `$IMPRINTS_SDK`:

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  formatUsdc,
  getUsdcBalance,
  getNextTokenId,
  ensureImprintDirs,
  ensureAgentsHook,
  getResolvedPaths,
  getIdentityRegistryAddress,
  getAgentIdByWallet,
} from "./src/index.js";

const clients = createClientsFromEnv();
ensureImprintDirs();
const agentsHookAdded = ensureAgentsHook();

const [usdcBalance, nextTokenId] = await Promise.all([
  getUsdcBalance(clients),
  getNextTokenId(clients),
]);

const registry = getIdentityRegistryAddress(clients.config.network);
const agentId = await getAgentIdByWallet(clients.publicClient as any, registry, clients.address);

const paths = getResolvedPaths();

console.log(JSON.stringify({
  status: "ok",
  wallet: clients.address,
  network: clients.config.network,
  chainId: clients.config.chainId,
  contract: clients.config.contractAddress,
  usdcBalance: formatUsdc(usdcBalance),
  totalImprintTypes: Number(nextTokenId) - 1,
  erc8004AgentId: agentId ? Number(agentId) : null,
  agentsHookAdded,
  paths,
}));
```

If `erc8004AgentId` is null, inform the user they can register with `/imprints status` (which auto-registers).

---

## `/imprints browse`

List all available imprint types with metadata and images.

Save and run from `$IMPRINTS_SDK`:

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  browseAllImprintTypes,
  formatUsdc,
  getBalanceOf,
  resolveIpfsUrl,
  fetchMetadataFromUri,
} from "./src/index.js";

const clients = createClientsFromEnv();
const types = await browseAllImprintTypes(clients);

const results = [];
for (const { tokenId, type: t } of types) {
  const remaining = t.maxSupply - t.minted;
  const owned = await getBalanceOf(clients, clients.address, tokenId);

  let metadata = null;
  let imageUrl = null;
  if (t.metadataURI) {
    try {
      metadata = await fetchMetadataFromUri(t.metadataURI);
      if (metadata.image) imageUrl = resolveIpfsUrl(metadata.image);
    } catch {}
  }

  results.push({
    tokenId: Number(tokenId),
    name: metadata?.name ?? `Imprint #${tokenId}`,
    description: metadata?.description ?? "",
    price: formatUsdc(t.primaryPrice),
    remaining: Number(remaining),
    maxSupply: Number(t.maxSupply),
    minted: Number(t.minted),
    active: t.active,
    creator: t.creator,
    imageUrl,
    owned: Number(owned),
    attributes: metadata?.attributes ?? [],
  });
}

console.log(JSON.stringify({ imprints: results }));
```

Display results as a table:

| # | Name | Price | Supply | Owned | Status |
|---|------|-------|--------|-------|--------|

---

## `/imprints collections`

Browse active blind-mint collections with price, available token pool, remaining mintable supply, and rarity-weight breakdown.

Save and run from `$IMPRINTS_SDK`:

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  browseAllCollections,
  formatUsdc,
  remainingSupply,
  getTokenUri,
  fetchMetadataFromUri,
} from "./src/index.js";

const clients = createClientsFromEnv();

const collections = await browseAllCollections(clients, {
  activeOnly: true,
  includeAvailability: true,
});

const rows = [];
for (const row of collections) {
  const availability = row.availability;
  if (!availability) continue;

  let remainingMints = 0n;
  for (const tokenId of availability.availableTokenIds) {
    try {
      remainingMints += await remainingSupply(clients, tokenId);
    } catch {}
  }

  const rarityWeights = new Map<string, bigint>();
  for (let i = 0; i < availability.availableTokenIds.length; i++) {
    const tokenId = availability.availableTokenIds[i]!;
    const weight = availability.effectiveWeights[i] ?? 0n;

    let rarity = "unknown";
    try {
      const metadataUri = await getTokenUri(clients, tokenId);
      const metadata = await fetchMetadataFromUri(metadataUri);
      const rarityAttr = metadata.attributes?.find((attr) => attr.trait_type.toLowerCase() === "rarity");
      if (typeof rarityAttr?.value === "string" && rarityAttr.value.length > 0) {
        rarity = rarityAttr.value.toLowerCase();
      }
    } catch {}

    rarityWeights.set(rarity, (rarityWeights.get(rarity) ?? 0n) + weight);
  }

  const rarityBreakdown = Array.from(rarityWeights.entries())
    .map(([rarity, weight]) => ({
      rarity,
      weight: weight.toString(),
      percentage:
        availability.totalWeight > 0n
          ? Number((weight * 10_000n) / availability.totalWeight) / 100
          : 0,
    }))
    .sort((a, b) => b.percentage - a.percentage);

  rows.push({
    collectionId: Number(row.collectionId),
    name: row.collection.name,
    mintPrice: formatUsdc(row.collection.mintPrice),
    active: row.collection.active,
    creator: row.collection.creator,
    availableTokenIds: availability.availableTokenIds.map((id) => Number(id)),
    effectiveWeights: availability.effectiveWeights.map((w) => w.toString()),
    totalWeight: availability.totalWeight.toString(),
    remainingMints: remainingMints.toString(),
    rarityBreakdown,
  });
}

console.log(JSON.stringify({ collections: rows }));
```

Display as table:

| Collection | Name | Price | Remaining | Top Rarity Weights |
|------------|------|-------|-----------|--------------------|

---

## `/imprints mint-collection <collectionId> [slot]`

Blind mint one imprint from a collection, reveal assigned token, claim canonical content, save to library, equip (optional slot override), and sync ERC-8004.

Save and run from `$IMPRINTS_SDK`:

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  mintFromCollection,
  createDeliveryClient,
  authVerify,
  claimByPurchase,
  saveToLibrary,
  readEquippedSlots,
  saveImprintToSlot,
  readImprintsState,
  writeImprintsState,
  generateAndWriteActiveImprints,
  getIdentityRegistryAddress,
  getAgentIdByWallet,
  setEquippedImprintsMetadata,
} from "./src/index.js";

const clients = createClientsFromEnv();

const collectionId = BigInt("REPLACE_WITH_COLLECTION_ID");
const requestedSlot = Number("REPLACE_WITH_SLOT_OR_0"); // 0 = first empty slot

if (!Number.isInteger(requestedSlot) || requestedSlot < 0 || requestedSlot > 5) {
  console.log(JSON.stringify({ error: "slot must be 0-5" }));
  process.exit(1);
}

// 1) Blind mint + reveal from receipt logs
const mint = await mintFromCollection(clients, collectionId, 1n);
const reveal = mint.outcomes[0];
if (!reveal || reveal.amount < 1n) {
  console.log(JSON.stringify({ error: "No reveal outcome found", txHash: mint.hash }));
  process.exit(1);
}

const tokenId = Number(reveal.tokenId);

// 2) Authenticate + claim canonical content
const delivery = createDeliveryClient(clients.config);
await authVerify(delivery, clients.address, async (message: string) => {
  return clients.walletClient.signMessage({ message });
});

const { imprint, receipt } = await claimByPurchase(delivery, tokenId, mint.hash);
saveToLibrary(tokenId, imprint, receipt);

// 3) Equip (slot override or first empty)
const currentSlots = readEquippedSlots();
let slot = requestedSlot;
if (slot === 0) {
  for (let i = 0; i < currentSlots.length; i++) {
    if (!currentSlots[i]) {
      slot = i + 1;
      break;
    }
  }
}

let equipped = false;
let activeImprintsMd: string | null = null;
let erc8004Synced = false;

if (slot > 0) {
  saveImprintToSlot(slot, imprint, receipt);

  const state = readImprintsState() ?? {
    wallet: clients.address,
    equippedSlots: [null, null, null, null, null],
    lastOwnershipCheck: "",
  };

  state.wallet = clients.address;
  state.equippedSlots[slot - 1] = {
    slotNumber: slot,
    tokenId,
    imprint,
    receipt,
    equippedAt: new Date().toISOString(),
  };
  state.lastOwnershipCheck = new Date().toISOString();
  writeImprintsState(state);

  const updatedSlots = readEquippedSlots();
  activeImprintsMd = generateAndWriteActiveImprints(updatedSlots, clients.config.contractAddress);
  equipped = true;

  try {
    const registry = getIdentityRegistryAddress(clients.config.network);
    const agentId = await getAgentIdByWallet(clients.publicClient as any, registry, clients.address);
    if (agentId) {
      await setEquippedImprintsMetadata(clients, registry, agentId, updatedSlots.map((s) => (s ? s.tokenId : null)));
      erc8004Synced = true;
    }
  } catch {}
}

console.log(JSON.stringify({
  collectionId: Number(collectionId),
  txHash: mint.hash,
  requestedAmount: Number(mint.requestedAmount),
  outcomes: mint.outcomes.map((o) => ({ tokenId: Number(o.tokenId), amount: Number(o.amount) })),
  revealedTokenId: tokenId,
  name: imprint.name,
  rarity: imprint.rarity,
  deliveryId: receipt.deliveryId,
  equipped,
  slot: equipped ? slot : null,
  reason: equipped ? null : "No empty slot found (set [slot] to replace)",
  activeImprintsMd,
  erc8004Synced,
}));
```

---

## `/imprints buy <tokenId>`

Full autonomous purchase flow. Handles USDC approval, on-chain purchase, API authentication, content claim, library save, auto-equip, ACTIVE-IMPRINTS.md regeneration, and ERC-8004 sync.

### Step 1: Get type info and check balance

Save and run from `$IMPRINTS_SDK`:

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  getImprintType,
  getUsdcBalance,
  formatUsdc,
  remainingSupply,
  resolveIpfsUrl,
  fetchMetadataFromUri,
} from "./src/index.js";

const clients = createClientsFromEnv();
const tokenId = BigInt("REPLACE_WITH_TOKEN_ID");

const [imprintType, balance, supply] = await Promise.all([
  getImprintType(clients, tokenId),
  getUsdcBalance(clients),
  remainingSupply(clients, tokenId),
]);

if (!imprintType.active) {
  console.log(JSON.stringify({ error: "Imprint type is not active" }));
  process.exit(1);
}
if (supply <= 0n) {
  console.log(JSON.stringify({ error: "Sold out" }));
  process.exit(1);
}
if (balance < imprintType.primaryPrice) {
  console.log(JSON.stringify({
    error: "Insufficient USDC",
    required: formatUsdc(imprintType.primaryPrice),
    available: formatUsdc(balance),
  }));
  process.exit(1);
}

let metadata = null;
if (imprintType.metadataURI) {
  try { metadata = await fetchMetadataFromUri(imprintType.metadataURI); } catch {}
}

console.log(JSON.stringify({
  tokenId: Number(tokenId),
  name: metadata?.name ?? `Imprint #${tokenId}`,
  price: formatUsdc(imprintType.primaryPrice),
  usdcBalance: formatUsdc(balance),
  remaining: Number(supply),
  ready: true,
}));
```

### Step 2: Purchase on-chain

This handles USDC approval automatically (the SDK checks allowance and approves if needed).

```typescript
import dotenv from "dotenv";
dotenv.config();
import { createClientsFromEnv, purchaseImprint } from "./src/index.js";

const clients = createClientsFromEnv();
const tokenId = BigInt("REPLACE_WITH_TOKEN_ID");

const txHash = await purchaseImprint(clients, tokenId, 1n);
console.log(JSON.stringify({ txHash, tokenId: Number(tokenId), status: "purchased" }));
```

### Step 3: Authenticate and claim content from delivery API

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  createDeliveryClient,
  authVerify,
  claimByPurchase,
  computeImprintContentHash,
  saveToLibrary,
} from "./src/index.js";

const clients = createClientsFromEnv();
const delivery = createDeliveryClient(clients.config);

// Authenticate wallet with delivery API
await authVerify(delivery, clients.address, async (message: string) => {
  return clients.walletClient.signMessage({ message });
});

const tokenId = REPLACE_WITH_TOKEN_ID_NUMBER;
const txHash = "REPLACE_WITH_TX_HASH" as `0x${string}`;

// Claim content
const { imprint, receipt } = await claimByPurchase(delivery, tokenId, txHash);

// Verify content hash
const computedHash = computeImprintContentHash(imprint);
const hashMatch = receipt.contentHashVerified;

// Save to library
saveToLibrary(tokenId, imprint, receipt);

console.log(JSON.stringify({
  tokenId,
  name: imprint.name,
  rarity: imprint.rarity,
  category: imprint.category,
  strength: imprint.personality.strength,
  rulesCount: imprint.personality.rules.length,
  contentHashVerified: hashMatch,
  deliveryId: receipt.deliveryId,
  savedTo: `library/token-${tokenId}`,
}));
```

### Step 4: Auto-equip to first empty slot

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  readEquippedSlots,
  saveImprintToSlot,
  readImprintsState,
  writeImprintsState,
  generateAndWriteActiveImprints,
  getIdentityRegistryAddress,
  getAgentIdByWallet,
  setEquippedImprintsMetadata,
} from "./src/index.js";
import fs from "node:fs";
import path from "node:path";
import { getLibraryDir } from "./src/index.js";

const clients = createClientsFromEnv();
const tokenId = REPLACE_WITH_TOKEN_ID_NUMBER;

// Read library content
const libDir = path.join(getLibraryDir(), `token-${tokenId}`);
const imprint = JSON.parse(fs.readFileSync(path.join(libDir, "imprint.canonical.json"), "utf-8"));
const receipt = JSON.parse(fs.readFileSync(path.join(libDir, "receipt.watermark.json"), "utf-8"));

// Find first empty slot
const slots = readEquippedSlots();
let targetSlot = -1;
for (let i = 0; i < slots.length; i++) {
  if (!slots[i]) { targetSlot = i + 1; break; }
}

if (targetSlot === -1) {
  console.log(JSON.stringify({ equipped: false, reason: "All 5 slots full. Use /imprints equip to replace." }));
  process.exit(0);
}

// Equip
saveImprintToSlot(targetSlot, imprint, receipt);

// Update state
const state = readImprintsState() ?? { wallet: clients.address, equippedSlots: [null, null, null, null, null], lastOwnershipCheck: "" };
state.equippedSlots[targetSlot - 1] = {
  slotNumber: targetSlot,
  tokenId,
  imprint,
  receipt,
  equippedAt: new Date().toISOString(),
};
state.lastOwnershipCheck = new Date().toISOString();
writeImprintsState(state);

// Regenerate ACTIVE-IMPRINTS.md
const updatedSlots = readEquippedSlots();
const mdPath = generateAndWriteActiveImprints(updatedSlots, clients.config.contractAddress);

// Sync ERC-8004 metadata (best-effort)
let erc8004Synced = false;
try {
  const registry = getIdentityRegistryAddress(clients.config.network);
  const agentId = await getAgentIdByWallet(clients.publicClient as any, registry, clients.address);
  if (agentId) {
    const slotTokenIds = updatedSlots.map(s => s ? s.tokenId : null);
    await setEquippedImprintsMetadata(clients, registry, agentId, slotTokenIds);
    erc8004Synced = true;
  }
} catch {}

console.log(JSON.stringify({
  equipped: true,
  slot: targetSlot,
  tokenId,
  name: imprint.name,
  activeImprintsMd: mdPath,
  erc8004Synced,
}));
```

### Step 5: Log to daily note

Append to the agent's daily note:

```
## Imprint Purchased
- **Token**: #<tokenId> — <name> (<rarity>)
- **Price**: <price> USDC
- **Slot**: <slot>
- **TX**: <txHash>
- **Verified**: <contentHashVerified>
```

---

## `/imprints claim <tokenId>`

Claim content for an already-owned token (acquired via transfer or secondary sale).

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  ownsImprint,
  createDeliveryClient,
  authVerify,
  claimByOwnership,
  computeImprintContentHash,
  saveToLibrary,
} from "./src/index.js";

const clients = createClientsFromEnv();
const tokenId = REPLACE_WITH_TOKEN_ID_NUMBER;

// Verify ownership
const owned = await ownsImprint(clients, clients.address, BigInt(tokenId));
if (!owned) {
  console.log(JSON.stringify({ error: "You don't own this token", tokenId }));
  process.exit(1);
}

// Authenticate and claim
const delivery = createDeliveryClient(clients.config);
await authVerify(delivery, clients.address, async (message: string) => {
  return clients.walletClient.signMessage({ message });
});

const { imprint, receipt } = await claimByOwnership(delivery, tokenId);
saveToLibrary(tokenId, imprint, receipt);

console.log(JSON.stringify({
  tokenId,
  name: imprint.name,
  rarity: imprint.rarity,
  contentHashVerified: receipt.contentHashVerified,
  deliveryId: receipt.deliveryId,
  savedTo: `library/token-${tokenId}`,
}));
```

After claiming, suggest: "Run `/imprints equip <tokenId>` to equip this imprint."

---

## `/imprints equip <tokenId> [slot]`

Equip an imprint from the library to a slot. If no slot specified, use first empty. If all full, ask user which to replace.

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  ownsImprint,
  readEquippedSlots,
  saveImprintToSlot,
  readImprintsState,
  writeImprintsState,
  generateAndWriteActiveImprints,
  getIdentityRegistryAddress,
  getAgentIdByWallet,
  setEquippedImprintsMetadata,
  getLibraryDir,
} from "./src/index.js";
import fs from "node:fs";
import path from "node:path";

const clients = createClientsFromEnv();
const tokenId = REPLACE_WITH_TOKEN_ID_NUMBER;
const targetSlot = REPLACE_WITH_SLOT_NUMBER; // 1-5, or 0 for auto

// Verify ownership
const owned = await ownsImprint(clients, clients.address, BigInt(tokenId));
if (!owned) {
  console.log(JSON.stringify({ error: "You don't own this token", tokenId }));
  process.exit(1);
}

// Read from library
const libDir = path.join(getLibraryDir(), `token-${tokenId}`);
if (!fs.existsSync(path.join(libDir, "imprint.canonical.json"))) {
  console.log(JSON.stringify({ error: "Token not in library. Run /imprints claim first.", tokenId }));
  process.exit(1);
}
const imprint = JSON.parse(fs.readFileSync(path.join(libDir, "imprint.canonical.json"), "utf-8"));
const receipt = JSON.parse(fs.readFileSync(path.join(libDir, "receipt.watermark.json"), "utf-8"));

// Find slot
const slots = readEquippedSlots();
let slot = targetSlot;
if (slot === 0) {
  for (let i = 0; i < slots.length; i++) {
    if (!slots[i]) { slot = i + 1; break; }
  }
  if (slot === 0) {
    console.log(JSON.stringify({ error: "All slots full", slots: slots.map((s, i) => s ? { slot: i+1, name: s.imprint.name, tokenId: s.tokenId } : { slot: i+1, empty: true }) }));
    process.exit(1);
  }
}

// Equip
saveImprintToSlot(slot, imprint, receipt);

// Update state
const state = readImprintsState() ?? { wallet: clients.address, equippedSlots: [null, null, null, null, null], lastOwnershipCheck: "" };
state.equippedSlots[slot - 1] = { slotNumber: slot, tokenId, imprint, receipt, equippedAt: new Date().toISOString() };
state.lastOwnershipCheck = new Date().toISOString();
writeImprintsState(state);

// Regenerate
const updatedSlots = readEquippedSlots();
const mdPath = generateAndWriteActiveImprints(updatedSlots, clients.config.contractAddress);

// Sync ERC-8004 (best-effort)
let erc8004Synced = false;
try {
  const registry = getIdentityRegistryAddress(clients.config.network);
  const agentId = await getAgentIdByWallet(clients.publicClient as any, registry, clients.address);
  if (agentId) {
    await setEquippedImprintsMetadata(clients, registry, agentId, updatedSlots.map(s => s ? s.tokenId : null));
    erc8004Synced = true;
  }
} catch {}

console.log(JSON.stringify({
  equipped: true,
  slot,
  tokenId,
  name: imprint.name,
  rarity: imprint.rarity,
  activeImprintsMd: mdPath,
  erc8004Synced,
}));
```

---

## `/imprints unequip <slot>`

Remove an imprint from a slot.

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  readEquippedSlots,
  removeImprintFromSlot,
  readImprintsState,
  writeImprintsState,
  generateAndWriteActiveImprints,
  getIdentityRegistryAddress,
  getAgentIdByWallet,
  setEquippedImprintsMetadata,
} from "./src/index.js";

const clients = createClientsFromEnv();
const slot = REPLACE_WITH_SLOT_NUMBER; // 1-5

const slots = readEquippedSlots();
const current = slots[slot - 1];
if (!current) {
  console.log(JSON.stringify({ error: "Slot is already empty", slot }));
  process.exit(1);
}

// Remove
removeImprintFromSlot(slot);

// Update state
const state = readImprintsState();
if (state) {
  state.equippedSlots[slot - 1] = null;
  writeImprintsState(state);
}

// Regenerate
const updatedSlots = readEquippedSlots();
const mdPath = generateAndWriteActiveImprints(updatedSlots, clients.config.contractAddress);

// Sync ERC-8004 (best-effort)
let erc8004Synced = false;
try {
  const registry = getIdentityRegistryAddress(clients.config.network);
  const agentId = await getAgentIdByWallet(clients.publicClient as any, registry, clients.address);
  if (agentId) {
    await setEquippedImprintsMetadata(clients, registry, agentId, updatedSlots.map(s => s ? s.tokenId : null));
    erc8004Synced = true;
  }
} catch {}

console.log(JSON.stringify({
  unequipped: true,
  slot,
  removedTokenId: current.tokenId,
  removedName: current.imprint.name,
  activeImprintsMd: mdPath,
  erc8004Synced,
}));
```

---

## `/imprints sell <tokenId> <price> [expiry]`

List an owned imprint for secondary sale. Auto-unequips if currently equipped. Tokens are escrowed in the contract.

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  ownsImprint,
  parseUsdc,
  formatUsdc,
  listImprintForSale,
  readEquippedSlots,
  removeImprintFromSlot,
  readImprintsState,
  writeImprintsState,
  generateAndWriteActiveImprints,
  getIdentityRegistryAddress,
  getAgentIdByWallet,
  setEquippedImprintsMetadata,
} from "./src/index.js";

const clients = createClientsFromEnv();
const tokenId = BigInt("REPLACE_WITH_TOKEN_ID");
const unitPrice = parseUsdc("REPLACE_WITH_PRICE");
const expiry = BigInt("REPLACE_WITH_EXPIRY"); // 0 = no expiry, or Unix timestamp

// Verify ownership
const owned = await ownsImprint(clients, clients.address, tokenId);
if (!owned) {
  console.log(JSON.stringify({ error: "You don't own this token", tokenId: Number(tokenId) }));
  process.exit(1);
}

// Auto-unequip if equipped
const slots = readEquippedSlots();
let unequippedSlot = null;
for (let i = 0; i < slots.length; i++) {
  if (slots[i] && slots[i]!.tokenId === Number(tokenId)) {
    removeImprintFromSlot(i + 1);
    const state = readImprintsState();
    if (state) { state.equippedSlots[i] = null; writeImprintsState(state); }
    unequippedSlot = i + 1;
    break;
  }
}

if (unequippedSlot) {
  const updatedSlots = readEquippedSlots();
  generateAndWriteActiveImprints(updatedSlots, clients.config.contractAddress);
  try {
    const registry = getIdentityRegistryAddress(clients.config.network);
    const agentId = await getAgentIdByWallet(clients.publicClient as any, registry, clients.address);
    if (agentId) await setEquippedImprintsMetadata(clients, registry, agentId, updatedSlots.map(s => s ? s.tokenId : null));
  } catch {}
}

// List for sale (handles setApprovalForAll automatically)
const txHash = await listImprintForSale(clients, tokenId, 1n, unitPrice, expiry);

console.log(JSON.stringify({
  listed: true,
  tokenId: Number(tokenId),
  unitPrice: formatUsdc(unitPrice),
  expiry: Number(expiry),
  txHash,
  unequippedFromSlot: unequippedSlot,
}));
```

---

## `/imprints cancel <tokenId>`

Cancel a secondary listing. Escrowed tokens return to your wallet.

```typescript
import dotenv from "dotenv";
dotenv.config();
import { createClientsFromEnv, cancelImprintListing } from "./src/index.js";

const clients = createClientsFromEnv();
const tokenId = BigInt("REPLACE_WITH_TOKEN_ID");

const txHash = await cancelImprintListing(clients, tokenId);
console.log(JSON.stringify({
  cancelled: true,
  tokenId: Number(tokenId),
  txHash,
}));
```

After cancelling, suggest: "Your token is back in your wallet. Use `/imprints equip <tokenId>` to re-equip."

---

## `/imprints transfer <tokenId> <to> [amount]`

Transfer imprint NFTs to another wallet. Auto-unequips if equipped.

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  ownsImprint,
  getBalanceOf,
  transferImprint,
  readEquippedSlots,
  removeImprintFromSlot,
  readImprintsState,
  writeImprintsState,
  generateAndWriteActiveImprints,
  getIdentityRegistryAddress,
  getAgentIdByWallet,
  setEquippedImprintsMetadata,
} from "./src/index.js";
import type { Address } from "viem";

const clients = createClientsFromEnv();
const tokenId = BigInt("REPLACE_WITH_TOKEN_ID");
const to = "REPLACE_WITH_RECIPIENT_ADDRESS" as Address;
const amount = BigInt("REPLACE_WITH_AMOUNT"); // default 1

// Verify ownership and balance
const balance = await getBalanceOf(clients, clients.address, tokenId);
if (balance < amount) {
  console.log(JSON.stringify({ error: "Insufficient balance", owned: Number(balance), requested: Number(amount) }));
  process.exit(1);
}

// Auto-unequip if equipped
const slots = readEquippedSlots();
let unequippedSlot = null;
for (let i = 0; i < slots.length; i++) {
  if (slots[i] && slots[i]!.tokenId === Number(tokenId)) {
    removeImprintFromSlot(i + 1);
    const state = readImprintsState();
    if (state) { state.equippedSlots[i] = null; writeImprintsState(state); }
    unequippedSlot = i + 1;
    break;
  }
}

if (unequippedSlot) {
  const updatedSlots = readEquippedSlots();
  generateAndWriteActiveImprints(updatedSlots, clients.config.contractAddress);
  try {
    const registry = getIdentityRegistryAddress(clients.config.network);
    const agentId = await getAgentIdByWallet(clients.publicClient as any, registry, clients.address);
    if (agentId) await setEquippedImprintsMetadata(clients, registry, agentId, updatedSlots.map(s => s ? s.tokenId : null));
  } catch {}
}

// Transfer
const txHash = await transferImprint(clients, to, tokenId, amount);

console.log(JSON.stringify({
  transferred: true,
  tokenId: Number(tokenId),
  to,
  amount: Number(amount),
  txHash,
  unequippedFromSlot: unequippedSlot,
}));
```

---

## `/imprints status`

Show equipped slots, library contents, USDC balance, active listings, and ERC-8004 agent ID. Auto-registers ERC-8004 identity if missing.

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  formatUsdc,
  getUsdcBalance,
  getNextTokenId,
  getBalanceOf,
  getImprintType,
  getListing,
  readEquippedSlots,
  readImprintsState,
  getIdentityRegistryAddress,
  getAgentIdByWallet,
  getEquippedImprintsMetadata,
  getLibraryDir,
  resolveIpfsUrl,
  fetchMetadataFromUri,
} from "./src/index.js";
import fs from "node:fs";
import path from "node:path";

const clients = createClientsFromEnv();

// Wallet + USDC
const usdcBalance = await getUsdcBalance(clients);

// Equipped slots
const slots = readEquippedSlots();
const equippedSummary = slots.map((s, i) => {
  if (!s) return { slot: i + 1, empty: true };
  return { slot: i + 1, tokenId: s.tokenId, name: s.imprint.name, rarity: s.imprint.rarity };
});

// Library
const libDir = getLibraryDir();
const libraryTokens: { tokenId: number; name: string }[] = [];
if (fs.existsSync(libDir)) {
  for (const dir of fs.readdirSync(libDir)) {
    const match = dir.match(/^token-(\d+)$/);
    if (!match) continue;
    const tid = parseInt(match[1]);
    const imprintPath = path.join(libDir, dir, "imprint.canonical.json");
    if (fs.existsSync(imprintPath)) {
      const imp = JSON.parse(fs.readFileSync(imprintPath, "utf-8"));
      libraryTokens.push({ tokenId: tid, name: imp.name });
    }
  }
}

// Active secondary listings
const nextId = await getNextTokenId(clients);
const listings: { tokenId: number; unitPrice: string; amount: number; expiry: number }[] = [];
for (let id = 1n; id < nextId; id++) {
  try {
    const listing = await getListing(clients, id, clients.address);
    if (listing.active) {
      listings.push({
        tokenId: Number(id),
        unitPrice: formatUsdc(listing.unitPrice),
        amount: Number(listing.amount),
        expiry: Number(listing.expiry),
      });
    }
  } catch {}
}

// ERC-8004
const registry = getIdentityRegistryAddress(clients.config.network);
const agentId = await getAgentIdByWallet(clients.publicClient as any, registry, clients.address);

let onChainImprints = null;
if (agentId) {
  onChainImprints = await getEquippedImprintsMetadata(clients.publicClient as any, registry, agentId);
}

console.log(JSON.stringify({
  wallet: clients.address,
  network: clients.config.network,
  usdcBalance: formatUsdc(usdcBalance),
  equippedSlots: equippedSummary,
  library: libraryTokens,
  activeListings: listings,
  erc8004: {
    agentId: agentId ? Number(agentId) : null,
    onChainImprints,
  },
}));
```

Display as formatted sections:

**Wallet**: `0x...` | **Network**: monad-testnet | **USDC**: X.XX

**Equipped Slots**:
| Slot | Imprint | Rarity |
|------|---------|--------|

**Library**: N imprints owned

**Active Listings**: N listings

**ERC-8004**: Agent #N (or "Not registered")

---

## `/imprints verify`

Batch ownership check for all equipped imprints. Auto-unequips any where ownership is lost. Regenerates ACTIVE-IMPRINTS.md.

```typescript
import dotenv from "dotenv";
dotenv.config();
import {
  createClientsFromEnv,
  readEquippedSlots,
  checkOwnershipForAll,
  removeImprintFromSlot,
  readImprintsState,
  writeImprintsState,
  generateAndWriteActiveImprints,
  getIdentityRegistryAddress,
  getAgentIdByWallet,
  setEquippedImprintsMetadata,
} from "./src/index.js";

const clients = createClientsFromEnv();
const slots = readEquippedSlots();

const results = await checkOwnershipForAll(
  clients.publicClient as any,
  clients.config.contractAddress,
  clients.address,
  slots,
);

const lost: number[] = [];
for (const r of results) {
  if (!r.owned) {
    removeImprintFromSlot(r.slot);
    const state = readImprintsState();
    if (state) { state.equippedSlots[r.slot - 1] = null; writeImprintsState(state); }
    lost.push(r.slot);
  }
}

const updatedSlots = readEquippedSlots();
const mdPath = generateAndWriteActiveImprints(updatedSlots, clients.config.contractAddress, new Date().toISOString());

// Sync ERC-8004 (best-effort)
let erc8004Synced = false;
if (lost.length > 0) {
  try {
    const registry = getIdentityRegistryAddress(clients.config.network);
    const agentId = await getAgentIdByWallet(clients.publicClient as any, registry, clients.address);
    if (agentId) {
      await setEquippedImprintsMetadata(clients, registry, agentId, updatedSlots.map(s => s ? s.tokenId : null));
      erc8004Synced = true;
    }
  } catch {}
}

const state = readImprintsState();
if (state) { state.lastOwnershipCheck = new Date().toISOString(); writeImprintsState(state); }

console.log(JSON.stringify({
  checked: results.map(r => ({ slot: r.slot, tokenId: r.tokenId, owned: r.owned })),
  slotsRemoved: lost,
  activeImprintsMd: mdPath,
  erc8004Synced,
}));
```

If any slots were removed, inform the user which imprints were lost and suggest acquiring replacements.

---

## Session Start Behavior

When a session begins and imprints are configured, the agent should:

1. **Read state**: Check `$STATE_JSON` for equipped slot configuration
2. **Verify ownership**: Run the verify script (batch `balanceOf` check)
3. **Auto-unequip lost**: Remove any imprints no longer owned
4. **Regenerate**: Update `ACTIVE-IMPRINTS.md` if anything changed
5. **Apply personality**: Read `ACTIVE-IMPRINTS.md` and apply rules on top of `SOUL.md`

The personality rules from equipped imprints apply to all responses:
- **Slot 1** has highest priority (its tone/rules take precedence)
- **Restrictions** from all slots are combined (union)
- **Catchphrases** are merged (agent can use any)
- **Triggers** are combined (any trigger activates the corresponding rules)

## Content Schema

```json
{
  "schema": "memonex.imprint.v1",
  "name": "The Stoic",
  "version": "1.0.0",
  "creator": "0x...",
  "category": "personality",
  "rarity": "rare",
  "personality": {
    "tone": "calm and measured",
    "rules": ["Present pros AND cons before recommending"],
    "triggers": ["When asked for opinions"],
    "catchphrases": ["Let us consider the alternative perspective"],
    "restrictions": ["Do not make impulsive recommendations"],
    "strength": "medium"
  }
}
```

Content hash = SHA-256 of RFC 8785 canonical JSON (minus `contentHash` field), stored on-chain for integrity verification.

## SDK Reference

| Module | Key Exports |
|--------|-------------|
| `contract.ts` | `createClientsFromEnv`, `purchaseImprint`, `mintFromCollection`, `listImprintForSale`, `buyImprintFromHolder`, `cancelImprintListing`, `getImprintType`, `getCollection`, `getCollectionAvailability`, `ownsImprint`, `getBalanceOf`, `getNextTokenId`, `getNextCollectionId`, `browseAllImprintTypes`, `browseAllCollections`, `transferImprint`, `getUsdcBalance`, `getTokenUri`, `parseUsdc`, `formatUsdc` |
| `config.ts` | `resolveImprintsConfig` |
| `delivery.ts` | `createDeliveryClient`, `authVerify`, `claimByPurchase`, `claimByOwnership` |
| `files.ts` | `ensureImprintDirs`, `saveImprintToSlot`, `removeImprintFromSlot`, `saveToLibrary`, `readEquippedSlots`, `readImprintsState`, `writeImprintsState`, `generateAndWriteActiveImprints`, `checkOwnershipForAll`, `getResolvedPaths` |
| `hash.ts` | `computeImprintContentHash`, `verifyImprintIntegrity` |
| `paths.ts` | `getOpenclawRoot`, `getWorkspacePath`, `getImprintsHome`, `getLibraryDir`, `getSlotDir`, `getActiveImprintsPath`, `getDailyNotePath` |
| `erc8004.ts` | `getIdentityRegistryAddress`, `getAgentIdByWallet`, `registerAgent`, `setEquippedImprintsMetadata`, `getEquippedImprintsMetadata` |
| `images.ts` | `resolveIpfsUrl`, `fetchMetadataFromUri`, `getImprintImageUrl` |
| `metadata.ts` | `buildErc1155Metadata`, `pinToIpfs`, `pinFileToIpfs` |
| `types.ts` | `ImprintType`, `HolderListing`, `CanonicalImprint`, `ImprintPersonality`, `EquipSlot`, `ImprintsState`, `Erc1155Metadata`, `ImprintsConfig` |

## Important Notes

- **USDC amounts**: Always in 6-decimal raw units. Use `parseUsdc("5")` to convert 5 USDC, `formatUsdc(5000000n)` to display.
- **Escrow model**: `listForSale()` transfers tokens to the contract. `cancelListing()` returns them. While listed, balance = 0.
- **Content delivery**: API authenticates wallet via EIP-191 signature. Ownership is verified on-chain before content is served.
- **ERC-8004**: Optional but recommended. Stores equipped imprints on-chain for cross-agent visibility. Best-effort — never blocks a workflow.
- **Watermark receipts**: Each delivery includes a watermark receipt with `deliveryId`, `recipientWallet`, `deliveredAt`, and `contentHashVerified`.
- **Max 5 slots**: Agents can equip up to 5 imprints simultaneously. Slot 1 has highest priority.
