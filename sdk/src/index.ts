export { MEMONEX_IMPRINTS_ABI, ERC20_ABI } from "./abi.js";

export {
  parseUsdc,
  formatUsdc,
  createClients,
  createClientsFromEnv,
  purchaseImprint,
  mintFromCollection,
  listImprintForSale,
  buyImprintFromHolder,
  cancelImprintListing,
  adminMint,
  addImprintType,
  addImprintTypeWithSig,
  signImprintAuth,
  getImprintType,
  ownsImprint,
  remainingSupply,
  verifyContentHash,
  getListing,
  getBalanceOf,
  getNextTokenId,
  getNextCollectionId,
  getCollection,
  getCollectionAvailability,
  getTokenUri,
  browseAllImprintTypes,
  browseAllCollections,
  transferImprint,
  getUsdcBalance,
} from "./contract.js";
export type { ImprintsClients } from "./contract.js";

export { resolveImprintsConfig } from "./config.js";

export {
  computeImprintContentHash,
  verifyImprintIntegrity,
  canonicalizeForHash,
} from "./hash.js";

export {
  getOpenclawRoot,
  getWorkspacePath,
  getImprintsHome,
  getImprintsMemoryDir,
  getActiveImprintsPath,
  getImprintsStatePath,
  getLibraryDir,
  getSlotDir,
  getMemoryMdPath,
  getDailyNotePath,
} from "./paths.js";

export {
  ensureImprintDirs,
  saveImprintToSlot,
  removeImprintFromSlot,
  saveToLibrary,
  readImprintsState,
  writeImprintsState,
  readEquippedSlots,
  generateActiveImprintsMd,
  generateAndWriteActiveImprints,
  checkOwnershipForAll,
  getResolvedPaths,
  ensureAgentsHook,
} from "./files.js";

export {
  createDeliveryClient,
  authChallenge,
  authVerify,
  claimByPurchase,
  claimByOwnership,
} from "./delivery.js";
export type { DeliveryClient } from "./delivery.js";

export {
  buildErc1155Metadata,
  pinToIpfs,
  pinFileToIpfs,
} from "./metadata.js";

export {
  ERC8004_REGISTRIES,
  getIdentityRegistryAddress,
  getReputationRegistryAddress,
  getAgentIdByWallet,
  registerAgent,
  setEquippedImprintsMetadata,
  getEquippedImprintsMetadata,
} from "./erc8004.js";
export type { EquippedImprintsMetadata } from "./erc8004.js";

export {
  resolveIpfsUrl,
  fetchMetadataFromUri,
  getImprintImageUrl,
} from "./images.js";

export type {
  ImprintType,
  HolderListing,
  Collection,
  CollectionAvailability,
  CollectionMintOutcome,
  MintFromCollectionResult,
  ImprintRarity,
  ImprintStrength,
  ImprintPersonality,
  CanonicalImprint,
  WatermarkReceipt,
  EquipSlot,
  ImprintsState,
  AuthChallengeResponse,
  AuthVerifyResponse,
  DeliveryClaimRequest,
  DeliveryClaimResponse,
  Erc1155Attribute,
  Erc1155Metadata,
  ImprintsNetwork,
  ImprintsConfig,
} from "./types.js";
