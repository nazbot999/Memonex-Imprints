import {
  createPublicClient,
  createWalletClient,
  http,
  fallback,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
  type Chain,
  type Transport,
  type Account,
  parseUnits,
  formatUnits,
  parseEventLogs,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { MEMONEX_IMPRINTS_ABI, ERC20_ABI } from "./abi.js";
import { resolveImprintsConfig } from "./config.js";
import type {
  ImprintType,
  HolderListing,
  Collection,
  CollectionAvailability,
  CollectionMintOutcome,
  MintFromCollectionResult,
  ImprintsConfig,
} from "./types.js";

// ── Utilities ───────────────────────────────────────────────────

export function parseUsdc(amount: string | number): bigint {
  return parseUnits(String(amount), 6);
}

export function formatUsdc(raw: bigint): string {
  return formatUnits(raw, 6);
}

// ── Chain definitions ───────────────────────────────────────────

const monadTestnet: Chain = {
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: ["https://memonex-ipfs.memonex.workers.dev/rpc/monad-testnet"] } },
};

const monad: Chain = {
  id: 143,
  name: "Monad",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: [] } },
};

function getChain(config: ImprintsConfig): Chain {
  return config.network === "monad" ? monad : monadTestnet;
}

// ── Client creation ─────────────────────────────────────────────

export interface ImprintsClients {
  publicClient: PublicClient;
  walletClient: WalletClient<Transport, Chain, Account>;
  config: ImprintsConfig;
  address: Address;
}

function createFallbackTransport(cfg: ImprintsConfig, chain: Chain): Transport {
  const urls = cfg.rpcUrls.length > 0
    ? cfg.rpcUrls
    : chain.rpcUrls.default.http;

  if (urls.length === 0) {
    throw new Error(
      `No RPC URL configured for network ${cfg.network}. Set IMPRINTS_RPC_URLS (or MONAD_RPC_URL / RPC_URL).`,
    );
  }

  const transports = urls.map((u) => http(u, { timeout: 15_000 }));
  return fallback(transports, { rank: true, retryCount: 3, retryDelay: 500 });
}

export function createClients(privateKey: Hex, config?: ImprintsConfig): ImprintsClients {
  const cfg = config ?? resolveImprintsConfig();
  const chain = getChain(cfg);
  const transport = createFallbackTransport(cfg, chain);
  const account = privateKeyToAccount(privateKey);

  const publicClient = createPublicClient({ chain, transport });
  const walletClient = createWalletClient({ account, chain, transport });

  return { publicClient, walletClient, config: cfg, address: account.address };
}

export function createClientsFromEnv(): ImprintsClients {
  const pk = process.env.IMPRINTS_PRIVATE_KEY ?? process.env.PRIVATE_KEY ?? process.env.DEPLOYER_PRIVATE_KEY;
  if (!pk) throw new Error("No private key found (IMPRINTS_PRIVATE_KEY | PRIVATE_KEY | DEPLOYER_PRIVATE_KEY)");
  return createClients(pk as Hex);
}

// ── USDC helpers ────────────────────────────────────────────────

async function ensureUsdcAllowance(
  clients: ImprintsClients,
  amount: bigint,
): Promise<void> {
  const { publicClient, walletClient, config, address } = clients;

  const allowance = await publicClient.readContract({
    address: config.usdcAddress,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: [address, config.contractAddress],
  });

  if (allowance < amount) {
    const hash = await walletClient.writeContract({
      address: config.usdcAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [config.contractAddress, amount],
    });
    await publicClient.waitForTransactionReceipt({ hash });
  }
}

// ── Primary sales ───────────────────────────────────────────────

export async function purchaseImprint(
  clients: ImprintsClients,
  tokenId: bigint,
  amount: bigint,
): Promise<Hex> {
  const imprintType = await getImprintType(clients, tokenId);
  const totalCost = imprintType.primaryPrice * amount;
  await ensureUsdcAllowance(clients, totalCost);

  const hash = await clients.walletClient.writeContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "purchase",
    args: [tokenId, amount],
  });
  await clients.publicClient.waitForTransactionReceipt({ hash });
  return hash;
}

export async function mintFromCollection(
  clients: ImprintsClients,
  collectionId: bigint,
  amount: bigint = 1n,
): Promise<MintFromCollectionResult> {
  const collection = await getCollection(clients, collectionId);
  const totalCost = collection.mintPrice * amount;
  await ensureUsdcAllowance(clients, totalCost);

  const hash = await clients.walletClient.writeContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "mintFromCollection",
    args: [collectionId, amount],
  });
  const receipt = await clients.publicClient.waitForTransactionReceipt({ hash });

  const mintLogs = parseEventLogs({
    abi: MEMONEX_IMPRINTS_ABI,
    logs: receipt.logs,
    eventName: "CollectionMint",
    strict: false,
  });

  const outcomeMap = new Map<bigint, bigint>();
  for (const log of mintLogs) {
    if (log.address.toLowerCase() !== clients.config.contractAddress.toLowerCase()) continue;

    const logCollectionId = log.args?.collectionId;
    const tokenId = log.args?.tokenId;
    const mintedAmount = log.args?.amount;

    if (logCollectionId !== collectionId) continue;
    if (typeof tokenId !== "bigint" || typeof mintedAmount !== "bigint") continue;

    const current = outcomeMap.get(tokenId) ?? 0n;
    outcomeMap.set(tokenId, current + mintedAmount);
  }

  const outcomes: CollectionMintOutcome[] = Array.from(outcomeMap.entries()).map(([tokenId, mintedAmount]) => ({
    tokenId,
    amount: mintedAmount,
  }));

  if (outcomes.length === 0) {
    throw new Error("CollectionMint event not found in transaction receipt");
  }

  return {
    hash,
    collectionId,
    requestedAmount: amount,
    outcomes,
  };
}

// ── Secondary market ────────────────────────────────────────────

export async function listImprintForSale(
  clients: ImprintsClients,
  tokenId: bigint,
  amount: bigint,
  unitPrice: bigint,
  expiry: bigint = 0n,
): Promise<Hex> {
  const approved = await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "isApprovedForAll",
    args: [clients.address, clients.config.contractAddress],
  });
  if (!approved) {
    const approveHash = await clients.walletClient.writeContract({
      address: clients.config.contractAddress,
      abi: MEMONEX_IMPRINTS_ABI,
      functionName: "setApprovalForAll",
      args: [clients.config.contractAddress, true],
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: approveHash });
  }

  const hash = await clients.walletClient.writeContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "listForSale",
    args: [tokenId, amount, unitPrice, expiry],
  });
  await clients.publicClient.waitForTransactionReceipt({ hash });
  return hash;
}

export async function buyImprintFromHolder(
  clients: ImprintsClients,
  tokenId: bigint,
  seller: Address,
  amount: bigint,
  maxTotalPrice: bigint,
): Promise<Hex> {
  await ensureUsdcAllowance(clients, maxTotalPrice);

  const hash = await clients.walletClient.writeContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "buyFromHolder",
    args: [tokenId, seller, amount, maxTotalPrice],
  });
  await clients.publicClient.waitForTransactionReceipt({ hash });
  return hash;
}

export async function cancelImprintListing(
  clients: ImprintsClients,
  tokenId: bigint,
): Promise<Hex> {
  const hash = await clients.walletClient.writeContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "cancelListing",
    args: [tokenId],
  });
  await clients.publicClient.waitForTransactionReceipt({ hash });
  return hash;
}

// ── Admin ───────────────────────────────────────────────────────

export async function adminMint(
  clients: ImprintsClients,
  to: Address,
  tokenId: bigint,
  amount: bigint,
): Promise<Hex> {
  const hash = await clients.walletClient.writeContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "adminMint",
    args: [to, tokenId, amount, "0x"],
  });
  await clients.publicClient.waitForTransactionReceipt({ hash });
  return hash;
}

export async function addImprintType(
  clients: ImprintsClients,
  params: {
    creator: Address;
    metadataURI: string;
    maxSupply: bigint;
    primaryPrice: bigint;
    royaltyBps: bigint;
    contentHash: Hex;
    promoReserve: bigint;
  },
): Promise<{ hash: Hex; tokenId: bigint }> {
  const hash = await clients.walletClient.writeContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "addImprintType",
    args: [
      params.creator,
      params.metadataURI,
      params.maxSupply,
      params.primaryPrice,
      params.royaltyBps,
      params.contentHash,
      params.promoReserve,
    ],
  });
  const receipt = await clients.publicClient.waitForTransactionReceipt({ hash });

  const [created] = parseEventLogs({
    abi: MEMONEX_IMPRINTS_ABI,
    logs: receipt.logs,
    eventName: "ImprintTypeCreated",
    strict: false,
  });

  const tokenId = created?.args?.tokenId;
  if (typeof tokenId !== "bigint") {
    throw new Error("ImprintTypeCreated event not found in transaction receipt");
  }

  return { hash, tokenId };
}

export async function addImprintTypeWithSig(
  clients: ImprintsClients,
  params: {
    creator: Address;
    metadataURI: string;
    maxSupply: bigint;
    primaryPrice: bigint;
    royaltyBps: bigint;
    contentHash: Hex;
    deadline: bigint;
    signature: Hex;
  },
): Promise<{ hash: Hex; tokenId: bigint }> {
  const hash = await clients.walletClient.writeContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "addImprintTypeWithSig",
    args: [
      params.creator,
      params.metadataURI,
      params.maxSupply,
      params.primaryPrice,
      params.royaltyBps,
      params.contentHash,
      params.deadline,
      params.signature,
    ],
  });
  const receipt = await clients.publicClient.waitForTransactionReceipt({ hash });

  const [created] = parseEventLogs({
    abi: MEMONEX_IMPRINTS_ABI,
    logs: receipt.logs,
    eventName: "ImprintTypeCreatedWithSig",
    strict: false,
  });

  const tokenId = created?.args?.tokenId;
  if (typeof tokenId !== "bigint") {
    throw new Error("ImprintTypeCreatedWithSig event not found in transaction receipt");
  }

  return { hash, tokenId };
}

// ── EIP-712 signing (for creator registration) ──────────────────

export async function signImprintAuth(
  walletClient: WalletClient<Transport, Chain, Account>,
  contractAddress: Address,
  params: {
    creator: Address;
    contentHash: Hex;
    metadataURI: string;
    maxSupply: bigint;
    primaryPrice: bigint;
    royaltyBps: bigint;
    nonce: bigint;
    deadline: bigint;
  },
): Promise<Hex> {
  const chainId = await walletClient.getChainId();

  return walletClient.signTypedData({
    domain: {
      name: "MemonexImprints",
      version: "1",
      chainId: BigInt(chainId),
      verifyingContract: contractAddress,
    },
    types: {
      ImprintAuth: [
        { name: "creator", type: "address" },
        { name: "contentHash", type: "bytes32" },
        { name: "metadataURI", type: "string" },
        { name: "maxSupply", type: "uint256" },
        { name: "primaryPrice", type: "uint256" },
        { name: "royaltyBps", type: "uint96" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    },
    primaryType: "ImprintAuth",
    message: {
      creator: params.creator,
      contentHash: params.contentHash,
      metadataURI: params.metadataURI,
      maxSupply: params.maxSupply,
      primaryPrice: params.primaryPrice,
      royaltyBps: params.royaltyBps,
      nonce: params.nonce,
      deadline: params.deadline,
    },
  });
}

// ── View functions ──────────────────────────────────────────────

export async function getImprintType(clients: ImprintsClients, tokenId: bigint): Promise<ImprintType> {
  const result = await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "getImprintType",
    args: [tokenId],
  });

  const r = result as any;
  return {
    creator: r.creator,
    royaltyBps: Number(r.royaltyBps),
    maxSupply: r.maxSupply,
    minted: r.minted,
    promoReserve: r.promoReserve,
    promoMinted: r.promoMinted,
    primaryPrice: r.primaryPrice,
    contentHash: r.contentHash,
    active: r.active,
    adminMintLocked: r.adminMintLocked,
    collectionOnly: r.collectionOnly,
    metadataURI: r.metadataURI,
  };
}

export async function ownsImprint(
  clients: ImprintsClients,
  wallet: Address,
  tokenId: bigint,
): Promise<boolean> {
  return (await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "ownsImprint",
    args: [wallet, tokenId],
  })) as boolean;
}

export async function remainingSupply(clients: ImprintsClients, tokenId: bigint): Promise<bigint> {
  return (await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "remainingSupply",
    args: [tokenId],
  })) as bigint;
}

export async function verifyContentHash(
  clients: ImprintsClients,
  tokenId: bigint,
  claimedHash: Hex,
): Promise<boolean> {
  return (await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "verifyContentHash",
    args: [tokenId, claimedHash],
  })) as boolean;
}

export async function getListing(
  clients: ImprintsClients,
  tokenId: bigint,
  seller: Address,
): Promise<HolderListing> {
  const result = await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "getListing",
    args: [tokenId, seller],
  });

  const r = result as any;
  return {
    amount: r.amount,
    unitPrice: r.unitPrice,
    expiry: r.expiry,
    active: r.active,
  };
}

export async function getBalanceOf(
  clients: ImprintsClients,
  wallet: Address,
  tokenId: bigint,
): Promise<bigint> {
  return (await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "balanceOf",
    args: [wallet, tokenId],
  })) as bigint;
}

export async function getNextTokenId(clients: ImprintsClients): Promise<bigint> {
  return (await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "nextTokenId",
  })) as bigint;
}

export async function getNextCollectionId(clients: ImprintsClients): Promise<bigint> {
  return (await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "nextCollectionId",
  })) as bigint;
}

export async function getCollection(clients: ImprintsClients, collectionId: bigint): Promise<Collection> {
  const result = await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "getCollection",
    args: [collectionId],
  });

  const r = result as {
    name: string;
    mintPrice: bigint;
    tokenIds: bigint[];
    rarityWeights: bigint[];
    active: boolean;
    creator: Address;
  };

  return {
    name: r.name,
    mintPrice: r.mintPrice,
    tokenIds: r.tokenIds,
    rarityWeights: r.rarityWeights,
    active: r.active,
    creator: r.creator,
  };
}

export async function getCollectionAvailability(
  clients: ImprintsClients,
  collectionId: bigint,
): Promise<CollectionAvailability> {
  const [availableTokenIds, effectiveWeights, totalWeight] = (await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "getCollectionAvailability",
    args: [collectionId],
  })) as readonly [readonly bigint[], readonly bigint[], bigint];

  return {
    availableTokenIds: [...availableTokenIds],
    effectiveWeights: [...effectiveWeights],
    totalWeight,
  };
}

export async function getTokenUri(clients: ImprintsClients, tokenId: bigint): Promise<string> {
  return (await clients.publicClient.readContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "uri",
    args: [tokenId],
  })) as string;
}

export async function browseAllImprintTypes(
  clients: ImprintsClients,
): Promise<{ tokenId: bigint; type: ImprintType }[]> {
  const nextId = await getNextTokenId(clients);
  const results: { tokenId: bigint; type: ImprintType }[] = [];

  for (let id = 1n; id < nextId; id++) {
    try {
      const imprintType = await getImprintType(clients, id);
      results.push({ tokenId: id, type: imprintType });
    } catch {
      // Token ID may be invalid or reverted — skip
    }
  }

  return results;
}

export async function browseAllCollections(
  clients: ImprintsClients,
  opts?: { activeOnly?: boolean; includeAvailability?: boolean },
): Promise<Array<{ collectionId: bigint; collection: Collection; availability?: CollectionAvailability }>> {
  const nextId = await getNextCollectionId(clients);
  const results: Array<{ collectionId: bigint; collection: Collection; availability?: CollectionAvailability }> = [];

  for (let id = 1n; id < nextId; id++) {
    try {
      const collection = await getCollection(clients, id);
      if (opts?.activeOnly && !collection.active) continue;

      const row: { collectionId: bigint; collection: Collection; availability?: CollectionAvailability } = {
        collectionId: id,
        collection,
      };

      if (opts?.includeAvailability) {
        row.availability = await getCollectionAvailability(clients, id);
      }

      results.push(row);
    } catch {
      // Collection ID may be invalid or reverted — skip
    }
  }

  return results;
}

export async function transferImprint(
  clients: ImprintsClients,
  to: Address,
  tokenId: bigint,
  amount: bigint = 1n,
): Promise<Hex> {
  const hash = await clients.walletClient.writeContract({
    address: clients.config.contractAddress,
    abi: MEMONEX_IMPRINTS_ABI,
    functionName: "safeTransferFrom",
    args: [clients.address, to, tokenId, amount, "0x"],
  });
  await clients.publicClient.waitForTransactionReceipt({ hash });
  return hash;
}

export async function getUsdcBalance(
  clients: ImprintsClients,
  wallet?: Address,
): Promise<bigint> {
  return (await clients.publicClient.readContract({
    address: clients.config.usdcAddress,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [wallet ?? clients.address],
  })) as bigint;
}
