import type { Hex, Address } from "viem";
import type {
  ImprintsConfig,
  AuthChallengeResponse,
  AuthVerifyResponse,
  DeliveryClaimResponse,
} from "./types.js";

export interface DeliveryClient {
  baseUrl: string;
  jwt: string | null;
}

export function createDeliveryClient(config: ImprintsConfig): DeliveryClient {
  if (!config.apiBaseUrl) throw new Error("IMPRINTS_API_URL not configured");
  return { baseUrl: config.apiBaseUrl.replace(/\/$/, ""), jwt: null };
}

async function fetchJson<T>(url: string, init: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`API error ${res.status}: ${body}`);
  }
  return res.json() as Promise<T>;
}

// ── Auth ────────────────────────────────────────────────────────

export async function authChallenge(client: DeliveryClient, wallet: Address): Promise<AuthChallengeResponse> {
  return fetchJson(`${client.baseUrl}/auth/challenge`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ wallet }),
  });
}

export async function authVerify(
  client: DeliveryClient,
  wallet: Address,
  signFn: (message: string) => Promise<Hex>,
): Promise<AuthVerifyResponse> {
  const challenge = await authChallenge(client, wallet);
  const signature = await signFn(challenge.nonce);

  const response = await fetchJson<AuthVerifyResponse>(`${client.baseUrl}/auth/verify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ wallet, nonce: challenge.nonce, signature }),
  });

  client.jwt = response.token;
  return response;
}

// ── Delivery ────────────────────────────────────────────────────

function authHeaders(client: DeliveryClient): Record<string, string> {
  if (!client.jwt) throw new Error("Not authenticated — call authVerify first");
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${client.jwt}`,
  };
}

export async function claimByPurchase(
  client: DeliveryClient,
  tokenId: number,
  txHash: Hex,
): Promise<DeliveryClaimResponse> {
  return fetchJson(`${client.baseUrl}/deliveries/claim`, {
    method: "POST",
    headers: authHeaders(client),
    body: JSON.stringify({ tokenId, txHash }),
  });
}

export async function claimByOwnership(
  client: DeliveryClient,
  tokenId: number,
): Promise<DeliveryClaimResponse> {
  return fetchJson(`${client.baseUrl}/deliveries/claim-by-ownership`, {
    method: "POST",
    headers: authHeaders(client),
    body: JSON.stringify({ tokenId }),
  });
}
