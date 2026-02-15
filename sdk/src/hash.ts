import _canonicalize from "canonicalize";
import { createHash } from "crypto";
import type { Hex } from "viem";
import type { CanonicalImprint } from "./types.js";

// canonicalize is CJS; NodeNext resolves the default export as a module namespace
const canonicalize = _canonicalize as unknown as (input: unknown) => string | undefined;

/**
 * Deep-clone an object and remove `contentHash` and `signature` fields
 * before canonicalization.
 */
function stripHashFields(obj: Record<string, unknown>): Record<string, unknown> {
  const clone = JSON.parse(JSON.stringify(obj));
  delete clone.contentHash;
  delete clone.signature;
  return clone;
}

/**
 * RFC 8785 canonicalize, then return bytes.
 */
export function canonicalizeForHash(obj: Record<string, unknown>): Uint8Array {
  const stripped = stripHashFields(obj);
  const canonical = canonicalize(stripped);
  if (!canonical) throw new Error("Canonicalization returned empty");
  return new TextEncoder().encode(canonical);
}

/**
 * SHA-256 over RFC 8785 canonical JSON, returned as 0x-prefixed hex.
 */
export function computeImprintContentHash(imprintJson: CanonicalImprint): Hex {
  const bytes = canonicalizeForHash(imprintJson as unknown as Record<string, unknown>);
  const hash = createHash("sha256").update(bytes).digest("hex");
  return `0x${hash}` as Hex;
}

/**
 * Verify an imprint's content hash matches the expected on-chain hash.
 */
export function verifyImprintIntegrity(imprintJson: CanonicalImprint, expectedHash: Hex): boolean {
  const computed = computeImprintContentHash(imprintJson);
  return computed.toLowerCase() === expectedHash.toLowerCase();
}
