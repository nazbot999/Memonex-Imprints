// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {IMemonexImprints} from "./interfaces/IMemonexImprints.sol";

/// @title MemonexImprints
/// @notice ERC-1155 imprint contract with USDC primary sales, collection-based blind minting,
///         escrow-based secondary market, EIP-712 creator registration, promo reserves, and ERC-8004 indexer hooks.
contract MemonexImprints is
    IMemonexImprints,
    ERC1155Supply,
    ERC1155URIStorage,
    ERC2981,
    Ownable,
    Pausable,
    ReentrancyGuard,
    EIP712
{
    using SafeERC20 for IERC20;

    // =============================================================
    // Constants
    // =============================================================

    uint96 public constant MAX_BPS = 10_000;

    uint8 internal constant CHANGE_MINT = 0;
    uint8 internal constant CHANGE_TRANSFER_IN = 1;
    uint8 internal constant CHANGE_TRANSFER_OUT = 2;
    uint8 internal constant CHANGE_BURN = 3;

    bytes32 public constant IMPRINT_AUTH_TYPEHASH = keccak256(
        "ImprintAuth(address creator,bytes32 contentHash,string metadataURI,uint256 maxSupply,uint256 primaryPrice,uint96 royaltyBps,uint256 nonce,uint256 deadline)"
    );

    // =============================================================
    // Errors
    // =============================================================

    error ZeroAddress();
    error InvalidBps();
    error InvalidAmount();
    error InvalidPrice();
    error InvalidHash();
    error EmptyURI();
    error TokenNotFound(uint256 tokenId);
    error TokenInactive(uint256 tokenId);
    error SupplyExceeded(uint256 tokenId, uint256 requestedTotalMinted, uint256 maxSupply);
    error NotCreatorOrOwner();
    error NotListed(uint256 tokenId, address seller);
    error InsufficientListingAmount(uint256 tokenId, address seller, uint256 listed, uint256 requested);
    error ListingPriceMismatch(uint256 tokenId, address seller, uint256 currentUnitPrice, uint256 requestedUnitPrice);
    error InvalidERC1155Sender(address sender);
    error SelfPurchase();
    error TransfersPaused();
    error InvalidFeeSplit();
    error InvalidSignature();
    error DeadlineExpired();
    error ListingExpired();
    error SlippageExceeded(uint256 totalCost, uint256 maxTotalPrice);
    error AdminMintIsLocked(uint256 tokenId);
    error PromoReserveExceeded(uint256 tokenId, uint256 requested, uint256 remaining);
    error PromoReserveExceedsMaxSupply();

    error InvalidCollection(uint256 collectionId);
    error CollectionInactive(uint256 collectionId);
    error CollectionEmpty();
    error CollectionArrayLengthMismatch();
    error InvalidWeight(uint256 index);
    error DuplicateTokenInCollection(uint256 tokenId);
    error CollectionSoldOut(uint256 collectionId);
    error NotCollectionAdmin();

    // =============================================================
    // Storage
    // =============================================================

    IERC20 public immutable usdc;
    address public treasury;
    uint96 public platformFeeBps;
    uint96 public secondaryFeeBps;
    uint256 public nextTokenId = 1;
    uint256 public nextCollectionId = 1;

    mapping(uint256 tokenId => ImprintType) private _imprintTypes;
    mapping(uint256 tokenId => mapping(address seller => HolderListing)) private _holderListings;
    /// @notice Escrowed token balances held by the contract for secondary listings.
    mapping(uint256 tokenId => mapping(address seller => uint256)) private _escrowedBalances;
    /// @notice Per-creator nonce for EIP-712 replay protection.
    mapping(address => uint256) public creatorNonces;
    /// @notice Used EIP-712 digests (belt-and-suspenders replay protection).
    mapping(bytes32 => bool) private _usedDigests;

    mapping(uint256 collectionId => Collection) private _collections;
    mapping(address account => bool) public authorizedCollectionCreators;

    /// @notice Nonce used in blind mint pseudo-randomness seed derivation.
    uint256 private _mintNonce;

    // =============================================================
    // Constructor
    // =============================================================

    constructor(address usdc_, address treasury_, uint96 platformFeeBps_, uint96 secondaryFeeBps_)
        ERC1155("")
        Ownable(msg.sender)
        EIP712("MemonexImprints", "1")
    {
        if (usdc_ == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (platformFeeBps_ > MAX_BPS || secondaryFeeBps_ > MAX_BPS) revert InvalidBps();

        usdc = IERC20(usdc_);
        treasury = treasury_;
        platformFeeBps = platformFeeBps_;
        secondaryFeeBps = secondaryFeeBps_;
    }

    // =============================================================
    // Admin
    // =============================================================

    /// @notice Pauses market-sensitive operations.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses market-sensitive operations.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IMemonexImprints
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /// @inheritdoc IMemonexImprints
    function setPlatformFeeBps(uint96 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_BPS) revert InvalidBps();
        uint96 oldFeeBps = platformFeeBps;
        platformFeeBps = newFeeBps;
        emit PlatformFeeBpsUpdated(oldFeeBps, newFeeBps);
    }

    /// @inheritdoc IMemonexImprints
    function setSecondaryFeeBps(uint96 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_BPS) revert InvalidBps();
        uint96 oldFeeBps = secondaryFeeBps;
        secondaryFeeBps = newFeeBps;
        emit SecondaryFeeBpsUpdated(oldFeeBps, newFeeBps);
    }

    /// @inheritdoc IMemonexImprints
    function setCollectionCreatorAuthorization(address account, bool authorized) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        authorizedCollectionCreators[account] = authorized;
        emit CollectionCreatorAuthorizationUpdated(account, authorized);
    }

    /// @inheritdoc IMemonexImprints
    function addImprintType(
        address creator,
        string calldata metadataURI,
        uint256 maxSupply,
        uint256 primaryPrice,
        uint96 royaltyBps,
        bytes32 contentHash,
        uint256 promoReserve
    ) external onlyOwner returns (uint256 tokenId) {
        tokenId = _createImprintType(
            creator, metadataURI, maxSupply, primaryPrice, royaltyBps, contentHash, promoReserve
        );

        emit ImprintTypeCreated(tokenId, creator, maxSupply, primaryPrice, royaltyBps, contentHash, metadataURI);
    }

    /// @inheritdoc IMemonexImprints
    function addImprintTypeWithSig(
        address creator,
        string calldata metadataURI,
        uint256 maxSupply,
        uint256 primaryPrice,
        uint96 royaltyBps,
        bytes32 contentHash,
        uint256 deadline,
        bytes calldata signature
    ) external returns (uint256 tokenId) {
        if (block.timestamp > deadline) revert DeadlineExpired();

        uint256 nonce = creatorNonces[creator];

        bytes32 structHash = keccak256(
            abi.encode(
                IMPRINT_AUTH_TYPEHASH,
                creator,
                contentHash,
                keccak256(bytes(metadataURI)),
                maxSupply,
                primaryPrice,
                royaltyBps,
                nonce,
                deadline
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        if (_usedDigests[digest]) revert InvalidSignature();

        address signer = ECDSA.recover(digest, signature);
        if (signer != creator) revert InvalidSignature();

        _usedDigests[digest] = true;
        creatorNonces[creator] = nonce + 1;

        // No promoReserve for creator-registered types
        tokenId = _createImprintType(creator, metadataURI, maxSupply, primaryPrice, royaltyBps, contentHash, 0);

        emit ImprintTypeCreatedWithSig(
            tokenId, creator, msg.sender, maxSupply, primaryPrice, royaltyBps, contentHash, metadataURI
        );
    }

    /// @inheritdoc IMemonexImprints
    function setImprintActive(uint256 tokenId, bool active) external onlyOwner {
        ImprintType storage imprint = _getImprint(tokenId);
        imprint.active = active;
        emit ImprintStatusUpdated(tokenId, active);
    }

    /// @inheritdoc IMemonexImprints
    function lockAdminMint(uint256 tokenId) external onlyOwner {
        ImprintType storage imprint = _getImprint(tokenId);
        imprint.adminMintLocked = true;
        emit AdminMintLocked(tokenId);
    }

    /// @inheritdoc IMemonexImprints
    function createCollection(
        string calldata name,
        uint256 mintPrice,
        uint256[] calldata tokenIds,
        uint256[] calldata rarityWeights
    ) external returns (uint256 collectionId) {
        if (!_isCollectionCreatorAuthorized(msg.sender)) revert NotCollectionAdmin();
        if (bytes(name).length == 0) revert EmptyURI();
        if (mintPrice == 0) revert InvalidPrice();

        uint256 len = tokenIds.length;
        if (len == 0) revert CollectionEmpty();
        if (len != rarityWeights.length) revert CollectionArrayLengthMismatch();

        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = tokenIds[i];
            _getImprint(tokenId);

            if (rarityWeights[i] == 0) revert InvalidWeight(i);

            for (uint256 j = i + 1; j < len; ++j) {
                if (tokenId == tokenIds[j]) revert DuplicateTokenInCollection(tokenId);
            }
        }

        collectionId = nextCollectionId++;
        Collection storage collection = _collections[collectionId];
        collection.name = name;
        collection.mintPrice = mintPrice;
        collection.active = true;
        collection.creator = msg.sender;

        for (uint256 i = 0; i < len; ++i) {
            collection.tokenIds.push(tokenIds[i]);
            collection.rarityWeights.push(rarityWeights[i]);
        }

        emit CollectionCreated(collectionId, msg.sender, name, mintPrice);
    }

    /// @inheritdoc IMemonexImprints
    function deactivateCollection(uint256 collectionId) external {
        Collection storage collection = _getCollection(collectionId);
        _onlyCollectionAdmin(collection);

        collection.active = false;
        emit CollectionStatusUpdated(collectionId, false);
    }

    /// @inheritdoc IMemonexImprints
    function activateCollection(uint256 collectionId) external {
        Collection storage collection = _getCollection(collectionId);
        _onlyCollectionAdmin(collection);

        collection.active = true;
        emit CollectionStatusUpdated(collectionId, true);
    }

    // =============================================================
    // Primary sale
    // =============================================================

    /// @inheritdoc IMemonexImprints
    function purchase(uint256 tokenId, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();

        ImprintType storage imprint = _getImprint(tokenId);
        if (!imprint.active) revert TokenInactive(tokenId);

        uint256 requestedTotalMinted = uint256(imprint.minted) + amount;
        if (requestedTotalMinted > uint256(imprint.maxSupply)) {
            revert SupplyExceeded(tokenId, requestedTotalMinted, uint256(imprint.maxSupply));
        }

        uint256 totalPaid = imprint.primaryPrice * amount;
        uint256 platformFee = (totalPaid * platformFeeBps) / MAX_BPS;
        uint256 creatorRevenue = totalPaid - platformFee;

        usdc.safeTransferFrom(msg.sender, address(this), totalPaid);

        if (platformFee > 0) {
            usdc.safeTransfer(treasury, platformFee);
        }
        if (creatorRevenue > 0) {
            usdc.safeTransfer(imprint.creator, creatorRevenue);
        }

        imprint.minted = uint128(requestedTotalMinted);
        _mint(msg.sender, tokenId, amount, "");

        emit ImprintPurchased(msg.sender, tokenId, amount, totalPaid, platformFee, creatorRevenue);
    }

    /// @inheritdoc IMemonexImprints
    function mintFromCollection(uint256 collectionId) external {
        mintFromCollection(collectionId, 1);
    }

    /// @inheritdoc IMemonexImprints
    function mintFromCollection(uint256 collectionId, uint256 amount) public nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();

        Collection storage collection = _getCollection(collectionId);
        if (!collection.active) revert CollectionInactive(collectionId);

        uint256 totalPaid = collection.mintPrice * amount;
        uint256 platformFee = (totalPaid * platformFeeBps) / MAX_BPS;
        uint256 creatorRevenue = totalPaid - platformFee;

        usdc.safeTransferFrom(msg.sender, address(this), totalPaid);

        if (platformFee > 0) {
            usdc.safeTransfer(treasury, platformFee);
        }
        if (creatorRevenue > 0) {
            usdc.safeTransfer(collection.creator, creatorRevenue);
        }

        uint256 tokenSlots = collection.tokenIds.length;
        uint256[] memory mintedTokenIds = new uint256[](tokenSlots);
        uint256[] memory mintedTokenAmounts = new uint256[](tokenSlots);
        uint256 mintedTokenCount;

        for (uint256 i = 0; i < amount; ++i) {
            uint256 selectedTokenId = _selectTokenFromCollection(collectionId, collection);
            ImprintType storage imprint = _imprintTypes[selectedTokenId];

            uint256 requestedTotalMinted = uint256(imprint.minted) + 1;
            if (requestedTotalMinted > uint256(imprint.maxSupply)) {
                revert SupplyExceeded(selectedTokenId, requestedTotalMinted, uint256(imprint.maxSupply));
            }
            imprint.minted = uint128(requestedTotalMinted);

            bool found;
            for (uint256 j = 0; j < mintedTokenCount; ++j) {
                if (mintedTokenIds[j] == selectedTokenId) {
                    mintedTokenAmounts[j] += 1;
                    found = true;
                    break;
                }
            }

            if (!found) {
                mintedTokenIds[mintedTokenCount] = selectedTokenId;
                mintedTokenAmounts[mintedTokenCount] = 1;
                mintedTokenCount += 1;
            }
        }

        for (uint256 i = 0; i < mintedTokenCount; ++i) {
            uint256 selectedTokenId = mintedTokenIds[i];
            uint256 selectedAmount = mintedTokenAmounts[i];

            _mint(msg.sender, selectedTokenId, selectedAmount, "");
            emit CollectionMint(msg.sender, collectionId, selectedTokenId, selectedAmount);
        }
    }

    /// @inheritdoc IMemonexImprints
    function adminMint(address to, uint256 tokenId, uint256 amount, bytes calldata data) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        ImprintType storage imprint = _getImprint(tokenId);
        if (imprint.adminMintLocked) revert AdminMintIsLocked(tokenId);

        // Check promo reserve
        uint256 newPromoMinted = uint256(imprint.promoMinted) + amount;
        if (newPromoMinted > uint256(imprint.promoReserve)) {
            revert PromoReserveExceeded(tokenId, amount, uint256(imprint.promoReserve) - uint256(imprint.promoMinted));
        }

        // Check overall supply
        uint256 requestedTotalMinted = uint256(imprint.minted) + amount;
        if (requestedTotalMinted > uint256(imprint.maxSupply)) {
            revert SupplyExceeded(tokenId, requestedTotalMinted, uint256(imprint.maxSupply));
        }

        imprint.promoMinted = uint128(newPromoMinted);
        imprint.minted = uint128(requestedTotalMinted);
        _mint(to, tokenId, amount, data);

        emit AdminMinted(to, tokenId, amount, data);
    }

    // =============================================================
    // Secondary market (escrow-based)
    // =============================================================

    /// @inheritdoc IMemonexImprints
    function listForSale(uint256 tokenId, uint256 amount, uint256 unitPrice, uint64 expiry) external whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        if (unitPrice == 0) revert InvalidPrice();
        if (expiry != 0 && expiry <= block.timestamp) revert ListingExpired();
        if (amount > type(uint128).max) revert InvalidAmount();
        if (unitPrice > type(uint128).max) revert InvalidAmount();

        _getImprint(tokenId);

        // Transfer tokens from seller to contract (escrow)
        _safeTransferFrom(msg.sender, address(this), tokenId, amount, "");

        HolderListing storage listing = _holderListings[tokenId][msg.sender];
        if (listing.active) {
            if (listing.unitPrice != unitPrice) {
                revert ListingPriceMismatch(tokenId, msg.sender, listing.unitPrice, unitPrice);
            }

            uint256 newAmount = uint256(listing.amount) + amount;
            if (newAmount > type(uint128).max) revert InvalidAmount();

            listing.amount = uint128(newAmount);
            listing.expiry = expiry;
        } else {
            _holderListings[tokenId][msg.sender] =
                HolderListing({amount: uint128(amount), unitPrice: uint128(unitPrice), expiry: expiry, active: true});
        }

        _escrowedBalances[tokenId][msg.sender] += amount;

        emit ImprintListed(msg.sender, tokenId, amount, unitPrice, expiry);
    }

    /// @inheritdoc IMemonexImprints
    function cancelListing(uint256 tokenId) external {
        HolderListing storage listing = _holderListings[tokenId][msg.sender];
        if (!listing.active) revert NotListed(tokenId, msg.sender);

        uint256 escrowed = _escrowedBalances[tokenId][msg.sender];

        delete _holderListings[tokenId][msg.sender];
        _escrowedBalances[tokenId][msg.sender] = 0;

        // Return escrowed tokens
        if (escrowed > 0) {
            _safeTransferFrom(address(this), msg.sender, tokenId, escrowed, "");
        }

        emit ImprintListingCancelled(msg.sender, tokenId);
    }

    /// @inheritdoc IMemonexImprints
    function buyFromHolder(uint256 tokenId, address seller, uint256 amount, uint256 maxTotalPrice)
        external
        nonReentrant
        whenNotPaused
    {
        if (seller == address(0)) revert ZeroAddress();
        if (msg.sender == seller) revert SelfPurchase();
        if (amount == 0) revert InvalidAmount();

        _getImprint(tokenId);

        HolderListing storage listing = _holderListings[tokenId][seller];
        if (!listing.active) revert NotListed(tokenId, seller);
        if (listing.expiry != 0 && block.timestamp > listing.expiry) revert ListingExpired();
        if (listing.amount < amount) {
            revert InsufficientListingAmount(tokenId, seller, listing.amount, amount);
        }

        uint256 unitPrice = uint256(listing.unitPrice);
        uint256 totalPaid = unitPrice * amount;
        if (totalPaid > maxTotalPrice) revert SlippageExceeded(totalPaid, maxTotalPrice);

        // Effects: decrement listing and escrow before external calls
        listing.amount -= uint128(amount);
        _escrowedBalances[tokenId][seller] -= amount;
        if (listing.amount == 0) {
            delete _holderListings[tokenId][seller];
        }

        // Collect payment
        usdc.safeTransferFrom(msg.sender, address(this), totalPaid);

        // Transfer escrowed tokens to buyer
        _safeTransferFrom(address(this), msg.sender, tokenId, amount, "");

        // Funds split
        (address royaltyReceiver, uint256 royaltyAmount) = royaltyInfo(tokenId, totalPaid);
        uint256 platformFee = (totalPaid * secondaryFeeBps) / MAX_BPS;
        if (royaltyAmount + platformFee > totalPaid) revert InvalidFeeSplit();
        uint256 sellerProceeds = totalPaid - royaltyAmount - platformFee;

        if (platformFee > 0) {
            usdc.safeTransfer(treasury, platformFee);
        }
        if (royaltyAmount > 0) {
            usdc.safeTransfer(royaltyReceiver, royaltyAmount);
        }
        if (sellerProceeds > 0) {
            usdc.safeTransfer(seller, sellerProceeds);
        }

        emit ImprintBoughtFromHolder(
            msg.sender, seller, tokenId, amount, unitPrice, totalPaid, royaltyReceiver, royaltyAmount, platformFee
        );
    }

    // =============================================================
    // Holder operations
    // =============================================================

    /// @inheritdoc IMemonexImprints
    function burn(uint256 tokenId, uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        _burn(msg.sender, tokenId, amount);
        emit ImprintBurned(msg.sender, tokenId, amount);
    }

    /// @inheritdoc IMemonexImprints
    function updatePrice(uint256 tokenId, uint256 newPrice) external {
        if (newPrice == 0) revert InvalidPrice();
        _onlyCreatorOrOwner(tokenId);

        ImprintType storage imprint = _imprintTypes[tokenId];
        uint256 oldPrice = imprint.primaryPrice;
        imprint.primaryPrice = newPrice;

        emit ImprintPriceUpdated(tokenId, oldPrice, newPrice, msg.sender);
    }

    /// @inheritdoc IMemonexImprints
    function updateContentHash(uint256 tokenId, bytes32 newContentHash) external {
        if (newContentHash == bytes32(0)) revert InvalidHash();
        _onlyCreatorOrOwner(tokenId);

        ImprintType storage imprint = _imprintTypes[tokenId];
        bytes32 oldHash = imprint.contentHash;
        imprint.contentHash = newContentHash;

        emit ImprintContentHashUpdated(tokenId, oldHash, newContentHash, msg.sender);
    }

    /// @inheritdoc IMemonexImprints
    function updateMetadataURI(uint256 tokenId, string calldata newMetadataURI) external {
        if (bytes(newMetadataURI).length == 0) revert EmptyURI();
        _onlyCreatorOrOwner(tokenId);

        ImprintType storage imprint = _imprintTypes[tokenId];
        string memory oldMetadataURI = imprint.metadataURI;
        imprint.metadataURI = newMetadataURI;
        _setURI(tokenId, newMetadataURI);

        emit ImprintMetadataURIUpdated(tokenId, oldMetadataURI, newMetadataURI, msg.sender);
    }

    /// @inheritdoc IMemonexImprints
    function rescueERC1155(address tokenContract, address to, uint256 tokenId, uint256 amount, bytes calldata data)
        external
        onlyOwner
    {
        if (tokenContract == address(0) || to == address(0)) revert ZeroAddress();
        if (tokenContract == address(this)) revert InvalidERC1155Sender(tokenContract);

        ERC1155(tokenContract).safeTransferFrom(address(this), to, tokenId, amount, data);
    }

    // =============================================================
    // Views
    // =============================================================

    /// @inheritdoc IMemonexImprints
    function ownsImprint(address wallet, uint256 tokenId) external view returns (bool) {
        return balanceOf(wallet, tokenId) > 0;
    }

    /// @inheritdoc IMemonexImprints
    function remainingSupply(uint256 tokenId) external view returns (uint256) {
        ImprintType storage imprint = _getImprint(tokenId);
        return uint256(imprint.maxSupply) - uint256(imprint.minted);
    }

    /// @inheritdoc IMemonexImprints
    function verifyContentHash(uint256 tokenId, bytes32 claimedHash) external view returns (bool) {
        ImprintType storage imprint = _getImprint(tokenId);
        return imprint.contentHash == claimedHash;
    }

    /// @inheritdoc IMemonexImprints
    function getImprintType(uint256 tokenId) external view returns (ImprintType memory) {
        return _getImprint(tokenId);
    }

    /// @inheritdoc IMemonexImprints
    function getListing(uint256 tokenId, address seller) external view returns (HolderListing memory) {
        return _holderListings[tokenId][seller];
    }

    /// @inheritdoc IMemonexImprints
    function getCollection(uint256 collectionId) external view returns (Collection memory) {
        return _getCollection(collectionId);
    }

    /// @inheritdoc IMemonexImprints
    function getCollectionAvailability(uint256 collectionId)
        external
        view
        returns (uint256[] memory availableTokenIds, uint256[] memory effectiveWeights, uint256 totalWeight)
    {
        Collection storage collection = _getCollection(collectionId);
        uint256 len = collection.tokenIds.length;

        uint256[] memory tokenBuffer = new uint256[](len);
        uint256[] memory weightBuffer = new uint256[](len);
        uint256 count;

        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = collection.tokenIds[i];
            uint256 weight = collection.rarityWeights[i];
            ImprintType storage imprint = _imprintTypes[tokenId];

            if (weight > 0 && imprint.active && uint256(imprint.minted) < uint256(imprint.maxSupply)) {
                tokenBuffer[count] = tokenId;
                weightBuffer[count] = weight;
                totalWeight += weight;
                count += 1;
            }
        }

        availableTokenIds = new uint256[](count);
        effectiveWeights = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            availableTokenIds[i] = tokenBuffer[i];
            effectiveWeights[i] = weightBuffer[i];
        }
    }

    /// @notice Returns the EIP-712 domain separator.
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // =============================================================
    // ERC-1155 receiver (needed for escrow)
    // =============================================================

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(this)) revert InvalidERC1155Sender(msg.sender);
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        if (msg.sender != address(this)) revert InvalidERC1155Sender(msg.sender);
        return this.onERC1155BatchReceived.selector;
    }

    // =============================================================
    // Internal
    // =============================================================

    function _createImprintType(
        address creator,
        string calldata metadataURI,
        uint256 maxSupply,
        uint256 primaryPrice,
        uint96 royaltyBps,
        bytes32 contentHash,
        uint256 promoReserve
    ) internal returns (uint256 tokenId) {
        if (creator == address(0)) revert ZeroAddress();
        if (bytes(metadataURI).length == 0) revert EmptyURI();
        if (maxSupply == 0) revert InvalidAmount();
        if (maxSupply > type(uint128).max) revert InvalidAmount();
        if (primaryPrice == 0) revert InvalidPrice();
        if (royaltyBps > MAX_BPS) revert InvalidBps();
        if (uint256(royaltyBps) + uint256(secondaryFeeBps) > MAX_BPS) revert InvalidFeeSplit();
        if (contentHash == bytes32(0)) revert InvalidHash();
        if (promoReserve > type(uint128).max) revert InvalidAmount();
        if (promoReserve > maxSupply) revert PromoReserveExceedsMaxSupply();

        tokenId = nextTokenId++;

        _imprintTypes[tokenId] = ImprintType({
            creator: creator,
            royaltyBps: royaltyBps,
            maxSupply: uint128(maxSupply),
            minted: 0,
            promoReserve: uint128(promoReserve),
            promoMinted: 0,
            primaryPrice: primaryPrice,
            contentHash: contentHash,
            active: true,
            adminMintLocked: false,
            metadataURI: metadataURI
        });

        _setURI(tokenId, metadataURI);
        _setTokenRoyalty(tokenId, creator, royaltyBps);
    }

    function _onlyCreatorOrOwner(uint256 tokenId) internal view {
        ImprintType storage imprint = _getImprint(tokenId);
        if (msg.sender != owner() && msg.sender != imprint.creator) revert NotCreatorOrOwner();
    }

    function _onlyCollectionAdmin(Collection storage collection) internal view {
        if (msg.sender != owner() && msg.sender != collection.creator) revert NotCollectionAdmin();
    }

    function _isCollectionCreatorAuthorized(address account) internal view returns (bool) {
        return account == owner() || authorizedCollectionCreators[account];
    }

    function _getImprint(uint256 tokenId) internal view returns (ImprintType storage imprint) {
        imprint = _imprintTypes[tokenId];
        if (imprint.creator == address(0)) revert TokenNotFound(tokenId);
    }

    function _getCollection(uint256 collectionId) internal view returns (Collection storage collection) {
        collection = _collections[collectionId];
        if (collection.creator == address(0)) revert InvalidCollection(collectionId);
    }

    function _selectTokenFromCollection(uint256 collectionId, Collection storage collection)
        internal
        returns (uint256 selectedTokenId)
    {
        uint256 len = collection.tokenIds.length;
        uint256 totalWeight;

        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = collection.tokenIds[i];
            uint256 weight = collection.rarityWeights[i];
            ImprintType storage imprint = _imprintTypes[tokenId];

            if (weight > 0 && imprint.active && uint256(imprint.minted) < uint256(imprint.maxSupply)) {
                totalWeight += weight;
            }
        }

        if (totalWeight == 0) revert CollectionSoldOut(collectionId);

        uint256 seed = uint256(keccak256(abi.encodePacked(block.prevrandao, msg.sender, block.timestamp, _mintNonce++)));

        uint256 roll = seed % totalWeight;
        uint256 cumulative;

        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = collection.tokenIds[i];
            uint256 weight = collection.rarityWeights[i];
            ImprintType storage imprint = _imprintTypes[tokenId];

            if (weight == 0 || !imprint.active || uint256(imprint.minted) >= uint256(imprint.maxSupply)) {
                continue;
            }

            cumulative += weight;
            if (roll < cumulative) {
                return tokenId;
            }
        }

        revert CollectionSoldOut(collectionId);
    }

    /// @dev Emits ERC-8004 hook events on all mint/transfer/burn balance changes.
    ///      Pausing blocks peer transfers but allows mint/burn.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        // Allow contract escrow transfers even when paused
        if (paused() && from != address(0) && to != address(0) && from != address(this) && to != address(this)) {
            revert TransfersPaused();
        }

        super._update(from, to, ids, values);

        address operator = _msgSender();
        uint256 len = ids.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 id = ids[i];

            if (from == address(this) || to == address(this)) {
                continue;
            }

            if (from == address(0)) {
                emit ERC8004ImprintBalanceChanged(to, id, balanceOf(to, id), CHANGE_MINT, address(0), operator);
            } else if (to == address(0)) {
                emit ERC8004ImprintBalanceChanged(from, id, balanceOf(from, id), CHANGE_BURN, address(0), operator);
            } else {
                emit ERC8004ImprintBalanceChanged(from, id, balanceOf(from, id), CHANGE_TRANSFER_OUT, to, operator);
                emit ERC8004ImprintBalanceChanged(to, id, balanceOf(to, id), CHANGE_TRANSFER_IN, from, operator);
            }
        }
    }

    // =============================================================
    // Overrides
    // =============================================================

    function uri(uint256 tokenId) public view override(ERC1155, ERC1155URIStorage) returns (string memory) {
        return ERC1155URIStorage.uri(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
