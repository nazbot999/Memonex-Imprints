// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMemonexImprints
/// @notice Interface for the Memonex ERC-1155 imprint marketplace with escrow,
///         EIP-712 creator auth, and collection-based blind minting.
interface IMemonexImprints {
    /// @notice Metadata and economic params for one imprint type (one ERC-1155 token id).
    struct ImprintType {
        address creator;
        uint96 royaltyBps;
        uint128 maxSupply;
        uint128 minted;
        uint128 promoReserve;
        uint128 promoMinted;
        uint256 primaryPrice;
        bytes32 contentHash;
        bool active;
        bool adminMintLocked;
        string metadataURI;
    }

    /// @notice Secondary listing for a holder (escrowed tokens).
    struct HolderListing {
        uint128 amount;
        uint128 unitPrice;
        uint64 expiry;
        bool active;
    }

    /// @notice Collection used for blind minting.
    struct Collection {
        string name;
        uint256 mintPrice;
        uint256[] tokenIds;
        uint256[] rarityWeights;
        bool active;
        address creator;
    }

    // ── Errors ──────────────────────────────────────────────────────

    error AllowlistRequired();
    error NotAllowlisted();
    error ClaimLimitExceeded();
    error InvalidCollection(uint256 collectionId);

    // ── Events ──────────────────────────────────────────────────────

    event ImprintTypeCreated(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 maxSupply,
        uint256 primaryPrice,
        uint96 royaltyBps,
        bytes32 contentHash,
        string metadataURI
    );

    event ImprintTypeCreatedWithSig(
        uint256 indexed tokenId,
        address indexed creator,
        address indexed registrar,
        uint256 maxSupply,
        uint256 primaryPrice,
        uint96 royaltyBps,
        bytes32 contentHash,
        string metadataURI
    );

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    event PlatformFeeBpsUpdated(uint96 oldBps, uint96 newBps);

    event SecondaryFeeBpsUpdated(uint96 oldBps, uint96 newBps);

    event AdminMinted(address indexed to, uint256 indexed tokenId, uint256 amount, bytes data);

    event AdminMintLocked(uint256 indexed tokenId);

    event ImprintBurned(address indexed from, uint256 indexed tokenId, uint256 amount);

    event ImprintPriceUpdated(uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice, address indexed updater);

    event ImprintContentHashUpdated(uint256 indexed tokenId, bytes32 oldHash, bytes32 newHash, address indexed updater);

    event ImprintMetadataURIUpdated(
        uint256 indexed tokenId, string oldMetadataURI, string newMetadataURI, address indexed updater
    );

    event ImprintStatusUpdated(uint256 indexed tokenId, bool active);

    event ImprintListed(
        address indexed seller, uint256 indexed tokenId, uint256 amount, uint256 unitPrice, uint64 expiry
    );

    event ImprintListingCancelled(address indexed seller, uint256 indexed tokenId);

    event ImprintBoughtFromHolder(
        address indexed buyer,
        address indexed seller,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 unitPrice,
        uint256 totalPaid,
        address royaltyReceiver,
        uint256 royaltyAmount,
        uint256 platformFee
    );

    /// @notice ERC-8004 hook event for indexers to sync identity loadouts.
    /// @dev `changeType`: 0=MINT, 1=TRANSFER_IN, 2=TRANSFER_OUT, 3=BURN.
    event ERC8004ImprintBalanceChanged(
        address indexed account,
        uint256 indexed tokenId,
        uint256 newBalance,
        uint8 changeType,
        address indexed counterparty,
        address operator
    );

    event CollectionCreated(uint256 indexed collectionId, address indexed creator, string name, uint256 mintPrice);

    event CollectionMint(address indexed user, uint256 indexed collectionId, uint256 indexed tokenId, uint256 amount);

    event CollectionStatusUpdated(uint256 indexed collectionId, bool active);

    event CollectionCreatorAuthorizationUpdated(address indexed account, bool authorized);

    event AllowlistUpdated(uint256 indexed collectionId, address indexed wallet, bool status);

    event AllowlistRequirementChanged(uint256 indexed collectionId, bool required);

    event ClaimLimitChanged(uint256 indexed collectionId, uint256 limit);

    // ── Admin ──────────────────────────────────────────────────────

    function setTreasury(address newTreasury) external;

    function setPlatformFeeBps(uint96 newFeeBps) external;

    function setSecondaryFeeBps(uint96 newFeeBps) external;

    function addImprintType(
        address creator,
        string calldata metadataURI,
        uint256 maxSupply,
        uint256 primaryPrice,
        uint96 royaltyBps,
        bytes32 contentHash,
        uint256 promoReserve
    ) external returns (uint256 tokenId);

    function addImprintTypeWithSig(
        address creator,
        string calldata metadataURI,
        uint256 maxSupply,
        uint256 primaryPrice,
        uint96 royaltyBps,
        bytes32 contentHash,
        uint256 deadline,
        bytes calldata signature
    ) external returns (uint256 tokenId);

    function setImprintActive(uint256 tokenId, bool active) external;

    function lockAdminMint(uint256 tokenId) external;

    function rescueERC1155(address tokenContract, address to, uint256 tokenId, uint256 amount, bytes calldata data)
        external;

    function setCollectionCreatorAuthorization(address account, bool authorized) external;

    function createCollection(
        string calldata name,
        uint256 mintPrice,
        uint256[] calldata tokenIds,
        uint256[] calldata rarityWeights
    ) external returns (uint256 collectionId);

    function deactivateCollection(uint256 collectionId) external;

    function activateCollection(uint256 collectionId) external;

    function addToAllowlist(uint256 collectionId, address[] calldata wallets) external;

    function removeFromAllowlist(uint256 collectionId, address[] calldata wallets) external;

    function setAllowlistRequired(uint256 collectionId, bool required) external;

    function setClaimLimit(uint256 collectionId, uint256 maxPerWallet) external;

    // ── Primary sale ───────────────────────────────────────────────

    function mintFromCollection(uint256 collectionId) external;

    function mintFromCollection(uint256 collectionId, uint256 amount) external;

    function adminMint(address to, uint256 tokenId, uint256 amount, bytes calldata data) external;

    // ── Secondary market (escrow) ──────────────────────────────────

    function listForSale(uint256 tokenId, uint256 amount, uint256 unitPrice, uint64 expiry) external;

    function cancelListing(uint256 tokenId) external;

    function buyFromHolder(uint256 tokenId, address seller, uint256 amount, uint256 maxTotalPrice) external;

    // ── Holder operations ──────────────────────────────────────────

    function burn(uint256 tokenId, uint256 amount) external;

    function updatePrice(uint256 tokenId, uint256 newPrice) external;

    function updateContentHash(uint256 tokenId, bytes32 newContentHash) external;

    function updateMetadataURI(uint256 tokenId, string calldata newMetadataURI) external;

    // ── Views ──────────────────────────────────────────────────────

    function ownsImprint(address wallet, uint256 tokenId) external view returns (bool);

    function remainingSupply(uint256 tokenId) external view returns (uint256);

    function verifyContentHash(uint256 tokenId, bytes32 claimedHash) external view returns (bool);

    function getImprintType(uint256 tokenId) external view returns (ImprintType memory);

    function getListing(uint256 tokenId, address seller) external view returns (HolderListing memory);

    function getCollection(uint256 collectionId) external view returns (Collection memory);

    function allowlisted(uint256 collectionId, address wallet) external view returns (bool);

    function allowlistRequired(uint256 collectionId) external view returns (bool);

    function claimLimit(uint256 collectionId) external view returns (uint256);

    function claimedCount(uint256 collectionId, address wallet) external view returns (uint256);

    function getCollectionAvailability(uint256 collectionId)
        external
        view
        returns (uint256[] memory availableTokenIds, uint256[] memory effectiveWeights, uint256 totalWeight);

    function creatorNonces(address creator) external view returns (uint256);

    function nextCollectionId() external view returns (uint256);

    function authorizedCollectionCreators(address account) external view returns (bool);
}
