import type { Erc1155Metadata, Erc1155Attribute } from "./types.js";

/**
 * Build a standard ERC-1155 metadata JSON object.
 */
export function buildErc1155Metadata(
  name: string,
  description: string,
  imageCid: string,
  attributes?: Erc1155Attribute[],
  properties?: Record<string, unknown>,
): Erc1155Metadata {
  const metadata: Erc1155Metadata = {
    name,
    description,
    decimals: 0,
    attributes: attributes ?? [],
  };

  if (imageCid.trim().length > 0) {
    metadata.image = `ipfs://${imageCid}`;
  }

  if (properties && Object.keys(properties).length > 0) {
    metadata.properties = properties;
  }

  return metadata;
}

/**
 * Pin a JSON object to Pinata IPFS and return the CID.
 */
export async function pinToIpfs(
  data: unknown,
  pinataJwt: string,
  name?: string,
): Promise<string> {
  const body = JSON.stringify({
    pinataContent: data,
    pinataMetadata: { name: name ?? "memonex-imprint" },
  });

  const res = await fetch("https://api.pinata.cloud/pinning/pinJSONToIPFS", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${pinataJwt}`,
    },
    body,
  });

  if (!res.ok) {
    const err = await res.text().catch(() => "");
    throw new Error(`Pinata pin failed (${res.status}): ${err}`);
  }

  const result = (await res.json()) as { IpfsHash: string };
  return result.IpfsHash;
}

/**
 * Pin a binary file to Pinata IPFS and return the CID.
 */
export async function pinFileToIpfs(
  fileBuffer: Buffer,
  fileName: string,
  pinataJwt: string,
): Promise<string> {
  const blob = new Blob([new Uint8Array(fileBuffer)]);
  const formData = new FormData();
  formData.append("file", blob, fileName);
  formData.append("pinataMetadata", JSON.stringify({ name: fileName }));

  const res = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${pinataJwt}`,
    },
    body: formData,
  });

  if (!res.ok) {
    const err = await res.text().catch(() => "");
    throw new Error(`Pinata file pin failed (${res.status}): ${err}`);
  }

  const result = (await res.json()) as { IpfsHash: string };
  return result.IpfsHash;
}
