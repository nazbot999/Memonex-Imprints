import type { Address, Hex } from "viem";

// ── On-chain struct mappings ────────────────────────────────────

export interface ImprintType {
  creator: Address;
  royaltyBps: number;
  maxSupply: bigint;
  minted: bigint;
  promoReserve: bigint;
  promoMinted: bigint;
  primaryPrice: bigint;
  contentHash: Hex;
  active: boolean;
  adminMintLocked: boolean;
  metadataURI: string;
}

export interface HolderListing {
  amount: bigint;
  unitPrice: bigint;
  expiry: bigint;
  active: boolean;
}

export interface Collection {
  name: string;
  mintPrice: bigint;
  tokenIds: bigint[];
  rarityWeights: bigint[];
  active: boolean;
  creator: Address;
}

export interface CollectionAvailability {
  availableTokenIds: bigint[];
  effectiveWeights: bigint[];
  totalWeight: bigint;
}

export interface CollectionMintOutcome {
  tokenId: bigint;
  amount: bigint;
}

export interface MintFromCollectionResult {
  hash: Hex;
  collectionId: bigint;
  requestedAmount: bigint;
  outcomes: CollectionMintOutcome[];
}

// ── Canonical imprint schema ────────────────────────────────────

export type ImprintRarity = "common" | "uncommon" | "rare" | "legendary" | "mythic";
export type ImprintStrength = "subtle" | "medium" | "strong";

export interface ImprintPersonality {
  tone: string;
  rules: string[];
  triggers: string[];
  catchphrases: string[];
  restrictions: string[];
  strength: ImprintStrength;
}

export interface CanonicalImprint {
  schema: "memonex.imprint.v1";
  name: string;
  version: string;
  creator: Address;
  category: string;
  rarity: ImprintRarity;
  personality: ImprintPersonality;
  contentHash?: Hex;
}

// ── Equip slots ─────────────────────────────────────────────────

export interface WatermarkReceipt {
  deliveryId: string;
  tokenId: number;
  recipientWallet: Address;
  deliveredAt: string;
  contentHashVerified: boolean;
  watermarkVersion: number;
}

export interface EquipSlot {
  slotNumber: number;
  tokenId: number;
  imprint: CanonicalImprint;
  receipt: WatermarkReceipt;
  equippedAt: string;
}

export interface ImprintsState {
  wallet: Address;
  equippedSlots: (EquipSlot | null)[];
  lastOwnershipCheck: string;
}

// ── Delivery API types ──────────────────────────────────────────

export interface AuthChallengeResponse {
  nonce: string;
  expiresAt: number;
}

export interface AuthVerifyResponse {
  token: string;
  expiresAt: number;
}

export interface DeliveryClaimRequest {
  tokenId: number;
  txHash?: Hex;
}

export interface DeliveryClaimResponse {
  imprint: CanonicalImprint;
  receipt: WatermarkReceipt;
}

// ── ERC-1155 metadata ───────────────────────────────────────────

export interface Erc1155Attribute {
  trait_type: string;
  value: string | number;
}

export interface Erc1155Metadata {
  name: string;
  description: string;
  image?: string;
  decimals?: number;
  properties?: Record<string, unknown>;
  attributes?: Erc1155Attribute[];
}

// ── Network config ──────────────────────────────────────────────

export type ImprintsNetwork = "monad-testnet" | "monad";

export interface ImprintsConfig {
  network: ImprintsNetwork;
  chainId: number;
  contractAddress: Address;
  usdcAddress: Address;
  rpcUrls: string[];
  apiBaseUrl: string;
}
