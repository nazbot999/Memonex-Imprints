import type { ImprintsClients } from "./contract.js";
import { getTokenUri } from "./contract.js";
import type { Erc1155Metadata } from "./types.js";

const DEFAULT_IPFS_GATEWAY = "https://gateway.pinata.cloud/ipfs/";

/**
 * Convert an IPFS URI to an HTTP gateway URL.
 * Passes through HTTP/HTTPS URLs unchanged.
 */
export function resolveIpfsUrl(uri: string, gateway?: string): string {
  if (uri.startsWith("ipfs://")) {
    const gw = gateway ?? process.env.MEMONEX_IPFS_GATEWAY ?? DEFAULT_IPFS_GATEWAY;
    const normalizedGw = gw.endsWith("/") ? gw : `${gw}/`;
    return `${normalizedGw}${uri.slice(7)}`;
  }
  return uri;
}

/**
 * Fetch ERC-1155 metadata JSON from a URI (IPFS or HTTP).
 */
export async function fetchMetadataFromUri(uri: string, gateway?: string): Promise<Erc1155Metadata> {
  const url = resolveIpfsUrl(uri, gateway);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch metadata from ${url}: ${res.status}`);
  return (await res.json()) as Erc1155Metadata;
}

/**
 * Read a token's URI from the contract, fetch metadata, and return the image URL.
 */
export async function getImprintImageUrl(
  clients: ImprintsClients,
  tokenId: bigint,
  gateway?: string,
): Promise<string | null> {
  try {
    const uri = await getTokenUri(clients, tokenId);
    if (!uri) return null;
    const metadata = await fetchMetadataFromUri(uri, gateway);
    if (!metadata.image) return null;
    return resolveIpfsUrl(metadata.image, gateway);
  } catch {
    return null;
  }
}
