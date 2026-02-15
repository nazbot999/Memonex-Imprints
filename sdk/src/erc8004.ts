import type { Address, Hex, PublicClient, Chain, Transport } from "viem";
import type { ImprintsClients } from "./contract.js";
import type { ImprintsNetwork } from "./types.js";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;

// ── Registry addresses per network ──────────────────────────────

export const ERC8004_REGISTRIES: Record<ImprintsNetwork, { identityRegistry: Address; reputationRegistry: Address }> = {
  "monad-testnet": {
    identityRegistry: "0x8004A818BFB912233c491871b3d84c89A494BD9e" as Address,
    reputationRegistry: "0x8004B663056A597Dffe9eCcC1965A193B7388713" as Address,
  },
  monad: {
    identityRegistry: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432" as Address,
    reputationRegistry: "0x8004BAa17C55a88189AE136b182e5fdA19dE9b63" as Address,
  },
};

// ── ABI ─────────────────────────────────────────────────────────

const IDENTITY_REGISTRY_ABI = [
  {
    type: "function",
    name: "register",
    stateMutability: "nonpayable",
    inputs: [{ name: "agentURI", type: "string" }],
    outputs: [{ name: "agentId", type: "uint256" }],
  },
  {
    type: "function",
    name: "tokenURI",
    stateMutability: "view",
    inputs: [{ name: "tokenId", type: "uint256" }],
    outputs: [{ name: "", type: "string" }],
  },
  {
    type: "function",
    name: "ownerOf",
    stateMutability: "view",
    inputs: [{ name: "agentId", type: "uint256" }],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "getMetadata",
    stateMutability: "view",
    inputs: [
      { name: "agentId", type: "uint256" },
      { name: "key", type: "string" },
    ],
    outputs: [{ name: "", type: "bytes" }],
  },
  {
    type: "function",
    name: "setMetadata",
    stateMutability: "nonpayable",
    inputs: [
      { name: "agentId", type: "uint256" },
      { name: "key", type: "string" },
      { name: "value", type: "bytes" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "getAgentWallet",
    stateMutability: "view",
    inputs: [{ name: "agentId", type: "uint256" }],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "tokenOfOwnerByIndex",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "index", type: "uint256" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

// ── Helpers ─────────────────────────────────────────────────────

export function getIdentityRegistryAddress(network: ImprintsNetwork): Address {
  const registry = ERC8004_REGISTRIES[network];
  if (!registry || registry.identityRegistry === ZERO_ADDRESS) {
    throw new Error(`ERC-8004 identity registry not configured for ${network}`);
  }
  return registry.identityRegistry;
}

export function getReputationRegistryAddress(network: ImprintsNetwork): Address {
  const registry = ERC8004_REGISTRIES[network];
  if (!registry || registry.reputationRegistry === ZERO_ADDRESS) {
    throw new Error(`ERC-8004 reputation registry not configured for ${network}`);
  }
  return registry.reputationRegistry;
}

// ── Agent identity functions ────────────────────────────────────

export async function getAgentIdByWallet(
  publicClient: PublicClient<Transport, Chain>,
  registry: Address,
  wallet: Address,
): Promise<bigint | null> {
  try {
    const balance = (await publicClient.readContract({
      address: registry,
      abi: IDENTITY_REGISTRY_ABI,
      functionName: "balanceOf",
      args: [wallet],
    })) as bigint;

    if (balance === 0n) return null;

    const agentId = (await publicClient.readContract({
      address: registry,
      abi: IDENTITY_REGISTRY_ABI,
      functionName: "tokenOfOwnerByIndex",
      args: [wallet, 0n],
    })) as bigint;

    return agentId;
  } catch {
    return null;
  }
}

export async function registerAgent(
  clients: ImprintsClients,
  registry: Address,
  agentURI: string,
): Promise<bigint> {
  const sim = await clients.publicClient.simulateContract({
    address: registry,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "register",
    args: [agentURI],
    account: clients.address,
  });

  const hash = await clients.walletClient.writeContract(sim.request as any);
  await clients.publicClient.waitForTransactionReceipt({ hash });

  // Read back the agent ID
  const agentId = await getAgentIdByWallet(
    clients.publicClient as PublicClient<Transport, Chain>,
    registry,
    clients.address,
  );
  if (!agentId) throw new Error("Registration succeeded but agent ID not found");
  return agentId;
}

// ── Equipped imprints metadata ──────────────────────────────────

const IMPRINTS_METADATA_KEY = "memonex.imprints.equipped";

export interface EquippedImprintsMetadata {
  slots: (number | null)[];
  updatedAt: string;
}

export async function setEquippedImprintsMetadata(
  clients: ImprintsClients,
  registry: Address,
  agentId: bigint,
  slots: (number | null)[],
): Promise<Hex> {
  const payload: EquippedImprintsMetadata = {
    slots,
    updatedAt: new Date().toISOString(),
  };
  const encoded = new TextEncoder().encode(JSON.stringify(payload));
  const hexValue = `0x${Buffer.from(encoded).toString("hex")}` as Hex;

  const hash = await clients.walletClient.writeContract({
    address: registry,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "setMetadata",
    args: [agentId, IMPRINTS_METADATA_KEY, hexValue],
  });
  await clients.publicClient.waitForTransactionReceipt({ hash });
  return hash;
}

export async function getEquippedImprintsMetadata(
  publicClient: PublicClient<Transport, Chain>,
  registry: Address,
  agentId: bigint,
): Promise<EquippedImprintsMetadata | null> {
  try {
    const raw = (await publicClient.readContract({
      address: registry,
      abi: IDENTITY_REGISTRY_ABI,
      functionName: "getMetadata",
      args: [agentId, IMPRINTS_METADATA_KEY],
    })) as Hex;

    if (!raw || raw === "0x" || raw === "0x0") return null;

    const bytes = Buffer.from(raw.slice(2), "hex");
    return JSON.parse(bytes.toString("utf-8")) as EquippedImprintsMetadata;
  } catch {
    return null;
  }
}
