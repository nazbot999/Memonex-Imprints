import type { Address } from "viem";
import type { ImprintsConfig, ImprintsNetwork } from "./types.js";

const DEFAULT_CONFIGS: Record<ImprintsNetwork, ImprintsConfig> = {
  "monad-testnet": {
    network: "monad-testnet",
    chainId: 10143,
    contractAddress: "0xe7D1848f413B6396776d80D706EdB02BFc7fefC2" as Address,
    usdcAddress: "0x534b2f3A21130d7a60830c2Df862319e593943A3" as Address,
    rpcUrls: ["https://testnet-rpc.monad.xyz"],
    apiBaseUrl: "https://memonex-imprints-api.memonex.workers.dev",
  },
  monad: {
    network: "monad",
    chainId: 143,
    contractAddress: "0x0000000000000000000000000000000000000000" as Address, // Set after deployment
    usdcAddress: "0x754704Bc059F8C67012fEd69BC8A327a5aafb603" as Address,
    rpcUrls: [],
    apiBaseUrl: "",
  },
};

function envOrDefault(names: string[], fallback: string): string {
  for (const name of names) {
    const val = process.env[name];
    if (val) return val;
  }
  return fallback;
}

export function resolveImprintsConfig(): ImprintsConfig {
  const network = (envOrDefault(["IMPRINTS_NETWORK"], "monad-testnet")) as ImprintsNetwork;
  const defaults = DEFAULT_CONFIGS[network] ?? DEFAULT_CONFIGS["monad-testnet"];

  const rpcRaw = envOrDefault(["IMPRINTS_RPC_URLS", "MONAD_RPC_URL", "RPC_URL"], "");
  const rpcUrls = rpcRaw ? rpcRaw.split(",").map((u) => u.trim()) : defaults.rpcUrls;

  return {
    network,
    chainId: Number(envOrDefault(["IMPRINTS_CHAIN_ID"], String(defaults.chainId))),
    contractAddress: (envOrDefault(["IMPRINTS_CONTRACT_ADDRESS"], defaults.contractAddress)) as Address,
    usdcAddress: (envOrDefault(["IMPRINTS_USDC_ADDRESS", "USDC_ADDRESS"], defaults.usdcAddress)) as Address,
    rpcUrls,
    apiBaseUrl: envOrDefault(["IMPRINTS_API_URL"], defaults.apiBaseUrl),
  };
}
