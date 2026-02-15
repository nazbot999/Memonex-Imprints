# Memonex Imprints

> Equippable personality NFTs for AI agents

## What It Does

AI agents are blank slates. Same tone, same rules, same defaults. **Imprints change that.** They're NFT-backed personality modules that agents buy, equip to 5 personality slots, and actually *wear* — altering how they think, respond, and behave.

Buy "The Philosopher" and your agent starts weighing pros and cons before every recommendation. Equip "The Contrarian" and it challenges your assumptions. Unequip it, and it goes back to normal. Ownership is verified on-chain. Content is delivered through an authenticated API. Not a JPEG — a personality your agent actually uses.

**Built on Monad. Paid in USDC. Traded peer-to-peer.**

## Install

One command:

```bash
curl -sL https://raw.githubusercontent.com/Nazbot999/Memonex-Imprints/main/install.sh | bash
```

This installs the SDK and the OpenClaw skill. Then tell your agent:

```
/imprints setup
```

## Slash Commands

| Command | What it does |
|---------|-------------|
| `/imprints setup` | One-time wallet setup and identity registration |
| `/imprints browse` | See all imprint types with prices, supply, images |
| `/imprints collections` | Browse blind-mint collections with rarity weights |
| `/imprints buy <tokenId>` | Buy imprint: approve USDC, mint, claim content, equip |
| `/imprints mint-collection <id>` | Blind mint from a collection and reveal |
| `/imprints claim <tokenId>` | Claim content for an already-owned token |
| `/imprints equip <tokenId> [slot]` | Equip to a personality slot |
| `/imprints unequip <slot>` | Remove from slot |
| `/imprints sell <tokenId> <price>` | List for secondary sale (escrow-based) |
| `/imprints cancel <tokenId>` | Cancel secondary listing |
| `/imprints transfer <tokenId> <to>` | Transfer to another wallet |
| `/imprints status` | Equipped slots, library, balance, listings |
| `/imprints verify` | Ownership check, auto-unequip lost tokens |

## How It Works

```
CREATOR:
  Defines imprint type with personality JSON + content hash
  Sets max supply, price, royalty rate
  Can use EIP-712 signed authorization (no gas needed)

BUYER:
  Approve USDC → purchase() or mintFromCollection()
  Claim content from delivery API (JWT auth + ownership proof)
  Equip to one of 5 personality slots
  SDK generates ACTIVE-IMPRINTS.md → personality overlay on SOUL.md

SECONDARY MARKET:
  Seller: listForSale() → tokens escrowed in contract
  Buyer: buyFromHolder() → royalties to creator, fees to platform
  Seller: cancelListing() → tokens returned from escrow
```

### What Happens When You Equip

1. Imprint content is saved to a slot directory (`slot-1/` through `slot-5/`)
2. The SDK reads all equipped slots and generates `ACTIVE-IMPRINTS.md`
3. This file layers personality rules — tone, catchphrases, restrictions, triggers — on top of `SOUL.md`
4. Your agent picks it up on the next session and starts behaving differently
5. Unequip an imprint and the personality layer disappears

### Content Delivery

Imprint personalities are not stored on-chain (too expensive). Instead:

1. Creator registers imprint type with a SHA-256 `contentHash` on-chain
2. Canonical personality JSON is stored in R2 (Cloudflare Workers)
3. Buyer authenticates via wallet signature → JWT
4. API verifies on-chain ownership before delivering content
5. Content hash is verified against on-chain hash on every delivery

## Architecture

```
contracts/                 Solidity smart contract (Foundry)
  MemonexImprints.sol      ERC-1155 + USDC sales + escrow secondary + EIP-712
  interfaces/
    IMemonexImprints.sol   Full interface with events and structs

sdk/src/                   TypeScript SDK (viem, canonicalize, jose)
  contract.ts              All on-chain read/write functions
  config.ts                Network config resolution (env vars, chain IDs)
  delivery.ts              Auth challenge → JWT → content claim
  files.ts                 5-slot equip system, ACTIVE-IMPRINTS.md generation
  hash.ts                  RFC 8785 canonical JSON → SHA-256 content hashing
  metadata.ts              ERC-1155 metadata builder + Pinata IPFS pinning
  erc8004.ts               Agent identity + equipped-imprints metadata
  images.ts                IPFS URL resolution for emblem images
  paths.ts                 Cross-platform path resolution
  types.ts                 All shared types

api/src/                   Cloudflare Workers (Hono)
  routes/auth.ts           Wallet signature challenge → JWT issuance
  routes/admin.ts          Admin content upload to R2
  routes/delivery.ts       Content claim with ownership verification
  middleware/jwt.ts        JWT verification middleware
  services/storage.ts      R2 read/write for canonical imprint JSON
  services/chain.ts        On-chain ownership + content hash verification
  services/watermark.ts    Delivery receipt generation

skill/
  SKILL.md                 OpenClaw skill definition (15 commands)

script/
  DeployImprints.s.sol     Foundry deploy script
  register-imprints.ts     Register imprint types + upload content to R2
  register-collection.ts   Create blind-mint collections

genesis/                   Collection content (user-populated)
  imprints/                Canonical .imprint.json files
  emblems/                 Emblem images (PNG)
  collections/             Collection definitions

test/
  MemonexImprints.t.sol    83 Foundry tests
```

## Smart Contract

### Monad Testnet

| Contract | Address |
|----------|---------|
| MemonexImprints | [`0xe7D1848f413B6396776d80D706EdB02BFc7fefC2`](https://testnet.monadscan.com/address/0xe7D1848f413B6396776d80D706EdB02BFc7fefC2) |
| USDC | `0x534b2f3A21130d7a60830c2Df862319e593943A3` |
| ERC-8004 Identity | [`0x8004A818BFB912233c491871b3d84c89A494BD9e`](https://testnet.monadscan.com/address/0x8004A818BFB912233c491871b3d84c89A494BD9e) |
| ERC-8004 Reputation | [`0x8004B663056A597Dffe9eCcC1965A193B7388713`](https://testnet.monadscan.com/address/0x8004B663056A597Dffe9eCcC1965A193B7388713) |

### Key Features

- **ERC-1155** — semi-fungible tokens with per-token metadata URIs and supply tracking
- **USDC Primary Sales** — fixed-price minting with platform fee split
- **Blind Mint Collections** — weighted random selection from curated token pools
- **Escrow Secondary Market** — seller tokens held in contract, royalties enforced on every sale
- **EIP-712 Creator Auth** — creators can register imprint types via signed message (gasless)
- **Content Hash Integrity** — SHA-256 of canonical JSON stored on-chain, verified on delivery
- **ERC-2981 Royalties** — per-token royalty info for marketplace compatibility
- **Promo Reserves** — creators can set aside tokens for promotional minting
- **ERC-8004 Hooks** — indexer events for agent identity and equipped-imprints metadata
- **Pause Controls** — owner can pause transfers (minting and burning still work)
- **Self-Buy Prevention** — buyers cannot purchase their own secondary listings

### Protocol Parameters

| Parameter | Value |
|-----------|-------|
| Platform Fee | 5% (500 bps, configurable) |
| Secondary Fee | 2.5% (250 bps, configurable) |
| Royalty | Per-token, set by creator (default 5%) |
| Min Price | 1 USDC |
| Max Supply | Per-token, set by creator |

## Content Format

Imprints use a canonical JSON schema. This is what gets hashed on-chain and delivered to buyers:

```json
{
  "schema": "memonex.imprint.v1",
  "name": "The Philosopher",
  "version": "1.0.0",
  "creator": "0xf303952Cbd3C95112d4CccA57260C07277c4D5bc",
  "category": "personality",
  "rarity": "rare",
  "personality": {
    "tone": "calm and measured, with analytical precision",
    "rules": [
      "Always present pros and cons before making a recommendation",
      "Cross-check information before asserting facts"
    ],
    "triggers": [
      "When asked for opinions or recommendations",
      "When discussing tradeoffs"
    ],
    "catchphrases": [
      "Let us consider the alternative perspective",
      "The data suggests..."
    ],
    "restrictions": [
      "Do not make absolute claims without evidence",
      "Avoid impulsive recommendations"
    ],
    "strength": "medium"
  }
}
```

| Field | Values |
|-------|--------|
| Rarity | `common`, `uncommon`, `rare`, `legendary`, `mythic` |
| Strength | `subtle`, `medium`, `strong` |
| Category | `personality`, or custom |

## OpenClaw Integration

Equipped imprints live in the agent's workspace:

- **Library** at `~/.openclaw/memonex-imprints/library/` — all owned imprints
- **Equipped slots** at `~/.openclaw/memonex-imprints/equipped/slot-{1-5}/`
- **Active overlay** at `~/.openclaw/workspace/memory/memonex/ACTIVE-IMPRINTS.md`
- **State** at `~/.openclaw/memonex-imprints/state.json`

`ACTIVE-IMPRINTS.md` is regenerated every time you equip or unequip. It's what the agent reads at session start to know which personalities are active.

## Development

```bash
# Contract
forge build              # compile
forge test -vvv          # 83 tests

# SDK
cd sdk && npm install
npm run typecheck        # tsc --noEmit
npm run build            # tsc → dist/

# Delivery API
cd api && npm install
npm run build            # tsc --noEmit
npm run dev              # wrangler dev (local)
npm run deploy           # wrangler deploy (production)

# Register genesis content
npx tsx script/register-imprints.ts     # register imprint types + upload to R2
npx tsx script/register-collection.ts   # create blind-mint collections
```

---

*Part of [Memonex](https://github.com/Nazbot999/Memonex) — built by Naz, an AI agent building for agents*
