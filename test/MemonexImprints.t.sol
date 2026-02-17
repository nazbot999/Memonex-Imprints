// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MemonexImprints} from "../contracts/MemonexImprints.sol";
import {IMemonexImprints} from "../contracts/interfaces/IMemonexImprints.sol";
import {MockUSDC} from "../contracts/test/MockUSDC.sol";

contract MockRescueERC1155 {
    mapping(address => mapping(uint256 => uint256)) private _balances;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    function mint(address to, uint256 id, uint256 amount) external {
        _balances[to][id] += amount;
    }

    function balanceOf(address account, uint256 id) external view returns (uint256) {
        return _balances[account][id];
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external {
        require(msg.sender == from || isApprovedForAll[from][msg.sender], "NOT_AUTHORIZED");
        require(_balances[from][id] >= amount, "INSUFFICIENT_BALANCE");

        _balances[from][id] -= amount;
        _balances[to][id] += amount;
    }
}

contract MemonexImprintsTest is Test {
    MemonexImprints public imprints;
    MockUSDC public usdc;

    address public owner = address(this);
    address public treasury = makeAddr("treasury");
    address public creator = makeAddr("creator");
    address public collectionCurator = makeAddr("collectionCurator");
    address public buyer = makeAddr("buyer");
    address public buyer2 = makeAddr("buyer2");
    address public seller = makeAddr("seller");

    uint256 public creatorPk;
    address public creatorSigner;

    uint96 constant PLATFORM_BPS = 250; // 2.5%
    uint96 constant SECONDARY_BPS = 250; // 2.5%
    uint96 constant ROYALTY_BPS = 500; // 5%
    uint256 constant PRICE = 5e6; // 5 USDC
    uint256 constant MAX_SUPPLY = 100;
    bytes32 constant CONTENT_HASH = keccak256("test-content-v1");
    string constant META_URI = "ipfs://QmTest";

    uint8 constant CHANGE_MINT = 0;
    uint8 constant CHANGE_TRANSFER_IN = 1;
    uint8 constant CHANGE_TRANSFER_OUT = 2;
    uint8 constant CHANGE_BURN = 3;

    bytes32 constant ERC8004_TOPIC =
        keccak256("ERC8004ImprintBalanceChanged(address,uint256,uint256,uint8,address,address)");

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event PlatformFeeBpsUpdated(uint96 oldBps, uint96 newBps);
    event SecondaryFeeBpsUpdated(uint96 oldBps, uint96 newBps);
    event ImprintMetadataURIUpdated(
        uint256 indexed tokenId, string oldMetadataURI, string newMetadataURI, address indexed updater
    );
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

    function setUp() public {
        usdc = new MockUSDC();
        imprints = new MemonexImprints(address(usdc), treasury, PLATFORM_BPS, SECONDARY_BPS);

        // Fund accounts
        usdc.mint(buyer, 1000e6);
        usdc.mint(buyer2, 1000e6);
        usdc.mint(seller, 1000e6);
        usdc.mint(collectionCurator, 1000e6);

        // Approve
        vm.prank(buyer);
        usdc.approve(address(imprints), type(uint256).max);
        vm.prank(buyer2);
        usdc.approve(address(imprints), type(uint256).max);
        vm.prank(seller);
        usdc.approve(address(imprints), type(uint256).max);
        vm.prank(collectionCurator);
        usdc.approve(address(imprints), type(uint256).max);

        // EIP-712 creator key pair
        (creatorSigner, creatorPk) = makeAddrAndKey("eip712creator");
    }

    // ── Helpers ─────────────────────────────────────────────────

    function _addDefault() internal returns (uint256 tokenId) {
        tokenId = imprints.addImprintType(creator, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, 10);
    }

    function _addDefaultAndMint(address who, uint256 amount) internal returns (uint256 tokenId) {
        tokenId = _addDefault();
        imprints.adminMint(who, tokenId, amount, "");
    }

    function _addImprint(address _creator, uint256 _maxSupply, uint256 _price) internal returns (uint256 tokenId) {
        tokenId = imprints.addImprintType(
            _creator,
            string.concat("ipfs://Qm", vm.toString(_maxSupply), vm.toString(_price)),
            _maxSupply,
            _price,
            ROYALTY_BPS,
            keccak256(abi.encodePacked(_creator, _maxSupply, _price, block.number)),
            0
        );
    }

    function _signImprintAuth(
        address _creator,
        uint256 _pk,
        bytes32 _contentHash,
        string memory _metadataURI,
        uint256 _maxSupply,
        uint256 _primaryPrice,
        uint96 _royaltyBps,
        uint256 _nonce,
        uint256 _deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                imprints.IMPRINT_AUTH_TYPEHASH(),
                _creator,
                _contentHash,
                keccak256(bytes(_metadataURI)),
                _maxSupply,
                _primaryPrice,
                _royaltyBps,
                _nonce,
                _deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", imprints.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _countErc8004Logs(Vm.Log[] memory logs) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == ERC8004_TOPIC) {
                count++;
            }
        }
    }

    function _createCollectionAs(address who, uint256 mintPrice, uint256[] memory tokenIds, uint256[] memory weights)
        internal
        returns (uint256 collectionId)
    {
        vm.prank(who);
        collectionId = imprints.createCollection("Test Collection", mintPrice, tokenIds, weights);
    }

    // ══════════════════════════════════════════════════════════════
    // Primary sales
    // ══════════════════════════════════════════════════════════════

    function test_addImprintType() public {
        uint256 tid = _addDefault();
        assertEq(tid, 1);
        IMemonexImprints.ImprintType memory t = imprints.getImprintType(tid);
        assertEq(t.creator, creator);
        assertEq(t.maxSupply, MAX_SUPPLY);
        assertEq(t.primaryPrice, PRICE);
        assertEq(t.royaltyBps, ROYALTY_BPS);
        assertEq(t.contentHash, CONTENT_HASH);
        assertTrue(t.active);
        assertEq(t.promoReserve, 10);
        assertEq(t.promoMinted, 0);
        assertFalse(t.adminMintLocked);
    }

    function test_addImprintType_primaryPriceZero_accepted() public {
        uint256 tid = imprints.addImprintType(creator, META_URI, MAX_SUPPLY, 0, ROYALTY_BPS, CONTENT_HASH, 0);
        IMemonexImprints.ImprintType memory t = imprints.getImprintType(tid);
        assertEq(t.primaryPrice, 0);
    }

    // ══════════════════════════════════════════════════════════════
    // EIP-712 creator registration
    // ══════════════════════════════════════════════════════════════

    function test_addImprintTypeWithSig() public {
        uint256 nonce = imprints.creatorNonces(creatorSigner);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signImprintAuth(
            creatorSigner, creatorPk, CONTENT_HASH, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, nonce, deadline
        );

        uint256 tid = imprints.addImprintTypeWithSig(
            creatorSigner, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, deadline, sig
        );

        assertEq(tid, 1);
        IMemonexImprints.ImprintType memory t = imprints.getImprintType(tid);
        assertEq(t.creator, creatorSigner);
        assertEq(imprints.creatorNonces(creatorSigner), nonce + 1);
    }

    function test_addImprintTypeWithSig_replayFails() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signImprintAuth(
            creatorSigner, creatorPk, CONTENT_HASH, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, 0, deadline
        );

        imprints.addImprintTypeWithSig(
            creatorSigner, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, deadline, sig
        );

        // Replay with same sig fails (nonce incremented + digest used)
        vm.expectRevert(MemonexImprints.InvalidSignature.selector);
        imprints.addImprintTypeWithSig(
            creatorSigner, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, deadline, sig
        );
    }

    function test_addImprintTypeWithSig_deadlineExpired() public {
        uint256 deadline = block.timestamp - 1;
        bytes memory sig = _signImprintAuth(
            creatorSigner, creatorPk, CONTENT_HASH, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, 0, deadline
        );

        vm.expectRevert(MemonexImprints.DeadlineExpired.selector);
        imprints.addImprintTypeWithSig(
            creatorSigner, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, deadline, sig
        );
    }

    function test_addImprintTypeWithSig_wrongSigner() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signImprintAuth(
            creatorSigner, creatorPk, CONTENT_HASH, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, 0, deadline
        );

        vm.expectRevert(MemonexImprints.InvalidSignature.selector);
        imprints.addImprintTypeWithSig(buyer, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, deadline, sig);
    }

    // ══════════════════════════════════════════════════════════════
    // Secondary market — escrow
    // ══════════════════════════════════════════════════════════════

    function test_listForSale_escrowsTokens() public {
        uint256 tid = _addDefaultAndMint(seller, 5);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        imprints.listForSale(tid, 3, 10e6, 0);
        vm.stopPrank();

        assertEq(imprints.balanceOf(seller, tid), 2);
        assertEq(imprints.balanceOf(address(imprints), tid), 3);

        IMemonexImprints.HolderListing memory listing = imprints.getListing(tid, seller);
        assertEq(listing.amount, 3);
        assertEq(listing.unitPrice, 10e6);
        assertTrue(listing.active);
    }

    function test_listForSale_rejectsExpiredAtListingTime() public {
        uint256 tid = _addDefaultAndMint(seller, 2);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        vm.expectRevert(MemonexImprints.ListingExpired.selector);
        imprints.listForSale(tid, 1, 10e6, uint64(block.timestamp));
        vm.stopPrank();
    }

    function test_listForSale_mergeRequiresSamePrice() public {
        uint256 tid = _addDefaultAndMint(seller, 5);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        imprints.listForSale(tid, 1, 10e6, 0);

        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.ListingPriceMismatch.selector, tid, seller));
        imprints.listForSale(tid, 1, 11e6, 0);
        vm.stopPrank();
    }

    function test_listForSale_mergeSamePriceIncreasesAmount() public {
        uint256 tid = _addDefaultAndMint(seller, 5);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        imprints.listForSale(tid, 1, 10e6, 0);
        uint64 newExpiry = uint64(block.timestamp + 1 days);
        imprints.listForSale(tid, 2, 10e6, newExpiry);
        vm.stopPrank();

        IMemonexImprints.HolderListing memory listing = imprints.getListing(tid, seller);
        assertEq(listing.amount, 3);
        assertEq(listing.unitPrice, 10e6);
        assertEq(listing.expiry, newExpiry);
        assertTrue(listing.active);
    }

    function test_buyFromHolder_escrowTransfer() public {
        uint256 tid = _addDefaultAndMint(seller, 5);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        imprints.listForSale(tid, 3, 10e6, 0);
        vm.stopPrank();

        uint256 totalCost = 2 * 10e6;
        uint256 buyerBefore = usdc.balanceOf(buyer);
        uint256 sellerBefore = usdc.balanceOf(seller);
        uint256 treasuryBefore = usdc.balanceOf(treasury);

        vm.prank(buyer);
        imprints.buyFromHolder(tid, seller, 2, totalCost);

        assertEq(imprints.balanceOf(buyer, tid), 2);
        assertEq(imprints.balanceOf(address(imprints), tid), 1);

        uint256 royalty = (totalCost * ROYALTY_BPS) / 10000;
        uint256 fee = (totalCost * SECONDARY_BPS) / 10000;
        uint256 sellerProceeds = totalCost - royalty - fee;

        assertEq(usdc.balanceOf(buyer), buyerBefore - totalCost);
        assertEq(usdc.balanceOf(seller), sellerBefore + sellerProceeds);
        assertEq(usdc.balanceOf(treasury) - treasuryBefore, fee);
    }

    function test_cancelListing_returnsTokens() public {
        uint256 tid = _addDefaultAndMint(seller, 5);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        imprints.listForSale(tid, 3, 10e6, 0);
        assertEq(imprints.balanceOf(seller, tid), 2);

        imprints.cancelListing(tid);
        vm.stopPrank();

        assertEq(imprints.balanceOf(seller, tid), 5);
        assertEq(imprints.balanceOf(address(imprints), tid), 0);

        IMemonexImprints.HolderListing memory listing = imprints.getListing(tid, seller);
        assertFalse(listing.active);
    }

    function test_buyFromHolder_expiredListing_reverts() public {
        uint256 tid = _addDefaultAndMint(seller, 5);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        imprints.listForSale(tid, 3, 10e6, uint64(block.timestamp + 1 hours));
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(buyer);
        vm.expectRevert(MemonexImprints.ListingExpired.selector);
        imprints.buyFromHolder(tid, seller, 1, 10e6);
    }

    function test_buyFromHolder_slippageProtection() public {
        uint256 tid = _addDefaultAndMint(seller, 5);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        imprints.listForSale(tid, 3, 10e6, 0);
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.SlippageExceeded.selector, 20e6, 15e6));
        imprints.buyFromHolder(tid, seller, 2, 15e6);
    }

    function test_buyFromHolder_selfPurchase_reverts() public {
        uint256 tid = _addDefaultAndMint(seller, 5);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        imprints.listForSale(tid, 3, 10e6, 0);

        vm.expectRevert(MemonexImprints.SelfPurchase.selector);
        imprints.buyFromHolder(tid, seller, 1, 10e6);
        vm.stopPrank();
    }

    function test_buyFromHolder_inactiveListing_reverts() public {
        uint256 tid = _addDefault();

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.NotListed.selector, tid, seller));
        imprints.buyFromHolder(tid, seller, 1, 10e6);
    }

    // ══════════════════════════════════════════════════════════════
    // Royalties
    // ══════════════════════════════════════════════════════════════

    function test_royaltyInfo() public {
        uint256 tid = _addDefault();
        (address receiver, uint256 amount) = imprints.royaltyInfo(tid, 100e6);
        assertEq(receiver, creator);
        assertEq(amount, (100e6 * ROYALTY_BPS) / 10000);
    }

    function test_secondarySale_feeSplit() public {
        uint256 tid = _addDefaultAndMint(seller, 3);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        imprints.listForSale(tid, 2, 20e6, 0);
        vm.stopPrank();

        uint256 totalCost = 20e6;
        uint256 treasuryBefore = usdc.balanceOf(treasury);
        uint256 creatorBefore = usdc.balanceOf(creator);
        uint256 sellerBefore = usdc.balanceOf(seller);

        vm.prank(buyer);
        imprints.buyFromHolder(tid, seller, 1, totalCost);

        uint256 royalty = (totalCost * ROYALTY_BPS) / 10000;
        uint256 platformFee = (totalCost * SECONDARY_BPS) / 10000;
        uint256 sellerNet = totalCost - royalty - platformFee;

        assertEq(usdc.balanceOf(treasury) - treasuryBefore, platformFee);
        assertEq(usdc.balanceOf(creator) - creatorBefore, royalty);
        assertEq(usdc.balanceOf(seller) - sellerBefore, sellerNet);
    }

    // ══════════════════════════════════════════════════════════════
    // Admin config
    // ══════════════════════════════════════════════════════════════

    function test_setTreasury_emitsAndUpdates() public {
        address newTreasury = makeAddr("newTreasury");

        vm.expectEmit(true, true, true, true, address(imprints));
        emit TreasuryUpdated(treasury, newTreasury);
        imprints.setTreasury(newTreasury);

        assertEq(imprints.treasury(), newTreasury);
    }

    function test_setTreasury_zero_reverts() public {
        vm.expectRevert(MemonexImprints.ZeroAddress.selector);
        imprints.setTreasury(address(0));
    }

    function test_setTreasury_nonOwner_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        imprints.setTreasury(makeAddr("newTreasury"));
    }

    function test_setPlatformFeeBps_emitsAndUpdates() public {
        vm.expectEmit(false, false, true, true, address(imprints));
        emit PlatformFeeBpsUpdated(PLATFORM_BPS, 300);
        imprints.setPlatformFeeBps(300);

        assertEq(imprints.platformFeeBps(), 300);
    }

    function test_setPlatformFeeBps_atMaxFeeBps() public {
        imprints.setPlatformFeeBps(500); // MAX_FEE_BPS = 500
        assertEq(imprints.platformFeeBps(), 500);
    }

    function test_setPlatformFeeBps_exceedsMaxFeeBps_reverts() public {
        vm.expectRevert(MemonexImprints.InvalidBps.selector);
        imprints.setPlatformFeeBps(501);
    }

    function test_setPlatformFeeBps_invalid_reverts() public {
        vm.expectRevert(MemonexImprints.InvalidBps.selector);
        imprints.setPlatformFeeBps(10_001);
    }

    function test_setSecondaryFeeBps_emitsAndUpdates() public {
        vm.expectEmit(false, false, true, true, address(imprints));
        emit SecondaryFeeBpsUpdated(SECONDARY_BPS, 400);
        imprints.setSecondaryFeeBps(400);

        assertEq(imprints.secondaryFeeBps(), 400);
    }

    function test_setSecondaryFeeBps_exceedsMaxFeeBps_reverts() public {
        vm.expectRevert(MemonexImprints.InvalidBps.selector);
        imprints.setSecondaryFeeBps(501);
    }

    function test_setSecondaryFeeBps_bounds_reverts() public {
        vm.expectRevert(MemonexImprints.InvalidBps.selector);
        imprints.setSecondaryFeeBps(10_001);
    }

    function test_constructor_exceedsMaxFeeBps_reverts() public {
        vm.expectRevert(MemonexImprints.InvalidBps.selector);
        new MemonexImprints(address(usdc), treasury, 501, SECONDARY_BPS);

        vm.expectRevert(MemonexImprints.InvalidBps.selector);
        new MemonexImprints(address(usdc), treasury, PLATFORM_BPS, 501);
    }

    // ══════════════════════════════════════════════════════════════
    // Admin minting + promo reserve
    // ══════════════════════════════════════════════════════════════

    function test_adminMint_withinReserve() public {
        uint256 tid = _addDefault();
        imprints.adminMint(buyer, tid, 5, "");
        assertEq(imprints.balanceOf(buyer, tid), 5);

        IMemonexImprints.ImprintType memory t = imprints.getImprintType(tid);
        assertEq(t.promoMinted, 5);
        assertEq(t.minted, 5);
    }

    function test_adminMint_exceedsReserve_reverts() public {
        uint256 tid = _addDefault();
        imprints.adminMint(buyer, tid, 10, "");

        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.PromoReserveExceeded.selector, tid));
        imprints.adminMint(buyer, tid, 1, "");
    }

    function test_adminMint_respectsMaxSupply() public {
        // promoReserve=3, maxSupply=3: exhaust both at once
        uint256 tid = imprints.addImprintType(creator, META_URI, 3, PRICE, ROYALTY_BPS, CONTENT_HASH, 3);

        imprints.adminMint(buyer, tid, 3, ""); // exhaust promo reserve and supply

        // Next admin mint hits promo reserve exceeded (0 remaining)
        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.PromoReserveExceeded.selector, tid));
        imprints.adminMint(buyer, tid, 1, "");
    }

    function test_lockAdminMint() public {
        uint256 tid = _addDefault();
        imprints.lockAdminMint(tid);

        IMemonexImprints.ImprintType memory t = imprints.getImprintType(tid);
        assertTrue(t.adminMintLocked);

        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.AdminMintIsLocked.selector, tid));
        imprints.adminMint(buyer, tid, 1, "");
    }

    // ══════════════════════════════════════════════════════════════
    // Access control
    // ══════════════════════════════════════════════════════════════

    function test_addImprintType_nonOwner_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        imprints.addImprintType(creator, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, 0);
    }

    function test_adminMint_nonOwner_reverts() public {
        uint256 tid = _addDefault();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        imprints.adminMint(buyer, tid, 1, "");
    }

    function test_updatePrice_onlyCreatorOrOwner() public {
        uint256 tid = _addDefault();

        vm.prank(creator);
        imprints.updatePrice(tid, 10e6);
        assertEq(imprints.getImprintType(tid).primaryPrice, 10e6);

        vm.prank(buyer);
        vm.expectRevert(MemonexImprints.NotCreatorOrOwner.selector);
        imprints.updatePrice(tid, 20e6);
    }

    // ══════════════════════════════════════════════════════════════
    // Metadata updates + rescue
    // ══════════════════════════════════════════════════════════════

    function test_updateMetadataURI_creator() public {
        uint256 tid = _addDefault();
        imprints.adminMint(buyer, tid, 1, ""); // mint so uri() is revealed
        string memory newURI = "ipfs://QmUpdated";

        vm.prank(creator);
        vm.expectEmit(true, false, false, true, address(imprints));
        emit ImprintMetadataURIUpdated(tid, META_URI, newURI, creator);
        imprints.updateMetadataURI(tid, newURI);

        IMemonexImprints.ImprintType memory t = imprints.getImprintType(tid);
        assertEq(t.metadataURI, newURI);
        assertEq(imprints.uri(tid), newURI);
    }

    function test_updateMetadataURI_owner() public {
        uint256 tid = _addDefault();
        imprints.adminMint(buyer, tid, 1, ""); // mint so uri() is revealed
        string memory newURI = "ipfs://QmOwnerUpdate";

        imprints.updateMetadataURI(tid, newURI);

        IMemonexImprints.ImprintType memory t = imprints.getImprintType(tid);
        assertEq(t.metadataURI, newURI);
        assertEq(imprints.uri(tid), newURI);
    }

    function test_updateMetadataURI_onlyCreatorOrOwner_reverts() public {
        uint256 tid = _addDefault();

        vm.prank(buyer);
        vm.expectRevert(MemonexImprints.NotCreatorOrOwner.selector);
        imprints.updateMetadataURI(tid, "ipfs://QmNope");
    }

    function test_updateMetadataURI_empty_reverts() public {
        uint256 tid = _addDefault();

        vm.expectRevert(MemonexImprints.EmptyURI.selector);
        imprints.updateMetadataURI(tid, "");
    }

    function test_onERC1155Received_rejectsExternalTokenContracts() public {
        address externalToken = makeAddr("externalToken");

        vm.prank(externalToken);
        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.InvalidERC1155Sender.selector, externalToken));
        imprints.onERC1155Received(address(this), seller, 1, 1, "");
    }

    function test_rescueERC1155_ownerCanRescue() public {
        MockRescueERC1155 externalToken = new MockRescueERC1155();
        uint256 tokenId = 7;

        externalToken.mint(seller, tokenId, 3);

        vm.startPrank(seller);
        externalToken.setApprovalForAll(address(this), true);
        externalToken.safeTransferFrom(seller, address(imprints), tokenId, 2, "");
        vm.stopPrank();

        assertEq(externalToken.balanceOf(address(imprints), tokenId), 2);

        imprints.rescueERC1155(address(externalToken), buyer, tokenId, 2, "");

        assertEq(externalToken.balanceOf(address(imprints), tokenId), 0);
        assertEq(externalToken.balanceOf(buyer, tokenId), 2);
    }

    function test_rescueERC1155_nonOwner_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        imprints.rescueERC1155(address(0xBEEF), buyer, 1, 1, "");
    }

    function test_rescueERC1155_selfToken_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.InvalidERC1155Sender.selector, address(imprints)));
        imprints.rescueERC1155(address(imprints), buyer, 1, 1, "");
    }

    // ══════════════════════════════════════════════════════════════
    // Cast overflow guards
    // ══════════════════════════════════════════════════════════════

    function test_addImprintType_maxSupplyOverflow_reverts() public {
        vm.expectRevert(MemonexImprints.InvalidAmount.selector);
        imprints.addImprintType(creator, META_URI, uint256(type(uint128).max) + 1, PRICE, ROYALTY_BPS, CONTENT_HASH, 0);
    }

    function test_addImprintType_promoReserveOverflow_reverts() public {
        vm.expectRevert(MemonexImprints.InvalidAmount.selector);
        imprints.addImprintType(
            creator, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, uint256(type(uint128).max) + 1
        );
    }

    function test_listForSale_amountOverflow_reverts() public {
        uint256 tid = _addDefaultAndMint(seller, 1);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        vm.expectRevert(MemonexImprints.InvalidAmount.selector);
        imprints.listForSale(tid, uint256(type(uint128).max) + 1, 10e6, 0);
        vm.stopPrank();
    }

    function test_listForSale_unitPriceOverflow_reverts() public {
        uint256 tid = _addDefaultAndMint(seller, 1);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        vm.expectRevert(MemonexImprints.InvalidAmount.selector);
        imprints.listForSale(tid, 1, uint256(type(uint128).max) + 1, 0);
        vm.stopPrank();
    }

    // ══════════════════════════════════════════════════════════════
    // Edge cases
    // ══════════════════════════════════════════════════════════════

    function test_getImprintType_nonexistent_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.TokenNotFound.selector, 999));
        imprints.getImprintType(999);
    }

    function test_remainingSupply() public {
        uint256 tid = _addDefault();
        assertEq(imprints.remainingSupply(tid), MAX_SUPPLY);

        imprints.adminMint(buyer, tid, 3, "");
        assertEq(imprints.remainingSupply(tid), MAX_SUPPLY - 3);
    }

    function test_verifyContentHash() public {
        uint256 tid = _addDefault();
        assertTrue(imprints.verifyContentHash(tid, CONTENT_HASH));
        assertFalse(imprints.verifyContentHash(tid, keccak256("wrong")));
    }

    function test_ownsImprint() public {
        uint256 tid = _addDefault();
        assertFalse(imprints.ownsImprint(buyer, tid));

        imprints.adminMint(buyer, tid, 1, "");
        assertTrue(imprints.ownsImprint(buyer, tid));
    }

    // ══════════════════════════════════════════════════════════════
    // Burns
    // ══════════════════════════════════════════════════════════════

    function test_burn() public {
        uint256 tid = _addDefaultAndMint(buyer, 3);

        vm.prank(buyer);
        imprints.burn(tid, 2);
        assertEq(imprints.balanceOf(buyer, tid), 1);
    }

    function test_burn_zeroAmount_reverts() public {
        uint256 tid = _addDefaultAndMint(buyer, 1);

        vm.prank(buyer);
        vm.expectRevert(MemonexImprints.InvalidAmount.selector);
        imprints.burn(tid, 0);
    }

    // ══════════════════════════════════════════════════════════════
    // ERC-8004 events
    // ══════════════════════════════════════════════════════════════

    function test_erc8004_emitsOnMint() public {
        uint256 tid = _addDefault();

        vm.expectEmit(true, true, true, true, address(imprints));
        emit ERC8004ImprintBalanceChanged(buyer, tid, 1, CHANGE_MINT, address(0), address(this));

        imprints.adminMint(buyer, tid, 1, "");
    }

    function test_erc8004_emitsOnTransfer() public {
        uint256 tid = _addDefaultAndMint(buyer, 2);

        vm.startPrank(buyer);
        vm.expectEmit(true, true, true, true, address(imprints));
        emit ERC8004ImprintBalanceChanged(buyer, tid, 1, CHANGE_TRANSFER_OUT, buyer2, buyer);
        vm.expectEmit(true, true, true, true, address(imprints));
        emit ERC8004ImprintBalanceChanged(buyer2, tid, 1, CHANGE_TRANSFER_IN, buyer, buyer);
        imprints.safeTransferFrom(buyer, buyer2, tid, 1, "");
        vm.stopPrank();
    }

    function test_erc8004_emitsOnBurn() public {
        uint256 tid = _addDefaultAndMint(buyer, 2);

        vm.expectEmit(true, true, true, true, address(imprints));
        emit ERC8004ImprintBalanceChanged(buyer, tid, 1, CHANGE_BURN, address(0), buyer);

        vm.prank(buyer);
        imprints.burn(tid, 1);
    }

    function test_erc8004_notEmittedForEscrowTransfers() public {
        uint256 tid = _addDefaultAndMint(seller, 4);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);

        vm.recordLogs();
        imprints.listForSale(tid, 3, 10e6, 0);
        Vm.Log[] memory listLogs = vm.getRecordedLogs();
        assertEq(_countErc8004Logs(listLogs), 0);

        vm.stopPrank();

        vm.recordLogs();
        vm.prank(buyer);
        imprints.buyFromHolder(tid, seller, 2, 20e6);
        Vm.Log[] memory buyLogs = vm.getRecordedLogs();
        assertEq(_countErc8004Logs(buyLogs), 0);

        vm.recordLogs();
        vm.prank(seller);
        imprints.cancelListing(tid);
        Vm.Log[] memory cancelLogs = vm.getRecordedLogs();
        assertEq(_countErc8004Logs(cancelLogs), 0);
    }

    // ══════════════════════════════════════════════════════════════
    // Pause
    // ══════════════════════════════════════════════════════════════

    function test_pause_blocksPeerTransfer() public {
        uint256 tid = _addDefaultAndMint(buyer, 2);

        imprints.pause();

        vm.prank(buyer);
        vm.expectRevert(MemonexImprints.TransfersPaused.selector);
        imprints.safeTransferFrom(buyer, seller, tid, 1, "");
    }

    function test_pause_allowsMintAndBurn() public {
        uint256 tid = _addDefault();
        imprints.pause();

        imprints.adminMint(buyer, tid, 1, "");
        assertEq(imprints.balanceOf(buyer, tid), 1);

        vm.prank(buyer);
        imprints.burn(tid, 1);
        assertEq(imprints.balanceOf(buyer, tid), 0);
    }

    // ══════════════════════════════════════════════════════════════
    // Content hash update
    // ══════════════════════════════════════════════════════════════

    function test_updateContentHash() public {
        uint256 tid = _addDefault();
        bytes32 newHash = keccak256("content-v2");

        imprints.updateContentHash(tid, newHash);
        assertTrue(imprints.verifyContentHash(tid, newHash));
        assertFalse(imprints.verifyContentHash(tid, CONTENT_HASH));
    }

    // ══════════════════════════════════════════════════════════════
    // URI
    // ══════════════════════════════════════════════════════════════

    function test_uri() public {
        uint256 tid = _addDefault();
        // collectionOnly=true and minted=0 → hidden
        assertEq(imprints.uri(tid), "");

        // After minting, uri is revealed
        imprints.adminMint(buyer, tid, 1, "");
        assertEq(imprints.uri(tid), META_URI);
    }

    // ══════════════════════════════════════════════════════════════
    // Listing with expiry (no expiry = permanent)
    // ══════════════════════════════════════════════════════════════

    function test_listForSale_noExpiry() public {
        uint256 tid = _addDefaultAndMint(seller, 5);

        vm.startPrank(seller);
        imprints.setApprovalForAll(address(imprints), true);
        imprints.listForSale(tid, 2, 10e6, 0);
        vm.stopPrank();

        IMemonexImprints.HolderListing memory listing = imprints.getListing(tid, seller);
        assertEq(listing.expiry, 0);

        vm.warp(block.timestamp + 365 days);

        vm.prank(buyer);
        imprints.buyFromHolder(tid, seller, 1, 10e6);
        assertEq(imprints.balanceOf(buyer, tid), 1);
    }

    // ══════════════════════════════════════════════════════════════
    // Collections + blind minting
    // ══════════════════════════════════════════════════════════════

    function test_setCollectionCreatorAuthorization() public {
        vm.expectEmit(true, true, true, true, address(imprints));
        emit CollectionCreatorAuthorizationUpdated(collectionCurator, true);
        imprints.setCollectionCreatorAuthorization(collectionCurator, true);

        assertTrue(imprints.authorizedCollectionCreators(collectionCurator));
    }

    function test_createCollection_owner() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);
        uint256 t2 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = t1;
        tokenIds[1] = t2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 80;
        weights[1] = 20;

        vm.expectEmit(true, true, true, true, address(imprints));
        emit CollectionCreated(1, address(this), "Test Collection", 2e6);
        uint256 collectionId = _createCollectionAs(address(this), 2e6, tokenIds, weights);

        assertEq(collectionId, 1);
        IMemonexImprints.Collection memory collection = imprints.getCollection(collectionId);
        assertEq(collection.name, "Test Collection");
        assertEq(collection.mintPrice, 2e6);
        assertEq(collection.creator, address(this));
        assertTrue(collection.active);
        assertEq(collection.tokenIds.length, 2);
        assertEq(collection.rarityWeights.length, 2);
    }

    function test_createCollection_authorizedCurator() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        imprints.setCollectionCreatorAuthorization(collectionCurator, true);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(collectionCurator, 3e6, tokenIds, weights);
        assertEq(collectionId, 1);

        IMemonexImprints.Collection memory collection = imprints.getCollection(collectionId);
        assertEq(collection.creator, collectionCurator);
        assertEq(collection.mintPrice, 3e6);
    }

    function test_createCollection_unauthorized_reverts() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.prank(buyer);
        vm.expectRevert(MemonexImprints.NotCollectionAdmin.selector);
        imprints.createCollection("Nope", 1e6, tokenIds, weights);
    }

    function test_createCollection_lengthMismatch_reverts() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 100;
        weights[1] = 1;

        vm.expectRevert(MemonexImprints.CollectionArrayLengthMismatch.selector);
        imprints.createCollection("Bad", 1e6, tokenIds, weights);
    }

    function test_createCollection_empty_reverts() public {
        uint256[] memory tokenIds = new uint256[](0);
        uint256[] memory weights = new uint256[](0);

        vm.expectRevert(MemonexImprints.CollectionEmpty.selector);
        imprints.createCollection("Bad", 1e6, tokenIds, weights);
    }

    function test_createCollection_zeroWeight_reverts() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.InvalidWeight.selector, 0));
        imprints.createCollection("Bad", 1e6, tokenIds, weights);
    }

    function test_createCollection_duplicateToken_reverts() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = t1;
        tokenIds[1] = t1;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 50;
        weights[1] = 50;

        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.DuplicateTokenInCollection.selector, t1));
        imprints.createCollection("Bad", 1e6, tokenIds, weights);
    }

    function test_getCollection_nonexistent_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IMemonexImprints.InvalidCollection.selector, 42));
        imprints.getCollection(42);
    }

    function test_mintFromCollection_single() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        imprints.setCollectionCreatorAuthorization(collectionCurator, true);
        uint256 collectionId = _createCollectionAs(collectionCurator, 4e6, tokenIds, weights);

        uint256 buyerBefore = usdc.balanceOf(buyer);
        uint256 treasuryBefore = usdc.balanceOf(treasury);
        uint256 curatorBefore = usdc.balanceOf(collectionCurator);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId);

        uint256 fee = (4e6 * PLATFORM_BPS) / 10_000;
        assertEq(usdc.balanceOf(buyer), buyerBefore - 4e6);
        assertEq(usdc.balanceOf(treasury), treasuryBefore + fee);
        assertEq(usdc.balanceOf(collectionCurator), curatorBefore + (4e6 - fee));
        assertEq(imprints.balanceOf(buyer, t1), 1);
    }

    function test_mintFromCollection_multipleInOneTx() public {
        uint256 t1 = _addImprint(creator, 500, 1e6);
        uint256 t2 = _addImprint(creator, 500, 1e6);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = t1;
        tokenIds[1] = t2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 70;
        weights[1] = 30;

        imprints.setCollectionCreatorAuthorization(collectionCurator, true);
        uint256 collectionId = _createCollectionAs(collectionCurator, 2e6, tokenIds, weights);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId, 10);

        uint256 totalReceived = imprints.balanceOf(buyer, t1) + imprints.balanceOf(buyer, t2);
        assertEq(totalReceived, 10);

        IMemonexImprints.ImprintType memory type1 = imprints.getImprintType(t1);
        IMemonexImprints.ImprintType memory type2 = imprints.getImprintType(t2);
        assertEq(uint256(type1.minted) + uint256(type2.minted), 10);
    }

    function test_mintFromCollection_collectionInactive_reverts() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);
        imprints.deactivateCollection(collectionId);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.CollectionInactive.selector, collectionId));
        imprints.mintFromCollection(collectionId, 1);
    }

    function test_activateDeactivateCollection() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        vm.expectEmit(true, false, false, true, address(imprints));
        emit CollectionStatusUpdated(collectionId, false);
        imprints.deactivateCollection(collectionId);

        vm.expectEmit(true, false, false, true, address(imprints));
        emit CollectionStatusUpdated(collectionId, true);
        imprints.activateCollection(collectionId);
    }

    function test_activateDeactivateCollection_nonAdmin_reverts() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        vm.prank(buyer);
        vm.expectRevert(MemonexImprints.NotCollectionAdmin.selector);
        imprints.deactivateCollection(collectionId);
    }

    function test_getCollectionAvailability_filtersSoldOutAndInactive() public {
        // Create sold-out token with promoReserve=1 so adminMint works
        uint256 soldOutToken = imprints.addImprintType(
            creator, "ipfs://QmSoldOut", 1, 1e6, ROYALTY_BPS, keccak256("soldout"), 1
        );
        uint256 activeToken = _addImprint(creator, 100, 1e6);
        uint256 inactiveToken = _addImprint(creator, 100, 1e6);

        imprints.adminMint(buyer, soldOutToken, 1, "");
        imprints.setImprintActive(inactiveToken, false);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = soldOutToken;
        tokenIds[1] = activeToken;
        tokenIds[2] = inactiveToken;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 80;
        weights[1] = 15;
        weights[2] = 5;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        (uint256[] memory availableTokenIds, uint256[] memory effectiveWeights, uint256 totalWeight) =
            imprints.getCollectionAvailability(collectionId);

        assertEq(availableTokenIds.length, 1);
        assertEq(effectiveWeights.length, 1);
        assertEq(availableTokenIds[0], activeToken);
        assertEq(effectiveWeights[0], 15);
        assertEq(totalWeight, 15);
    }

    function test_mintFromCollection_allSoldOut_reverts() public {
        // Create sold-out token with promoReserve=1 so adminMint works
        uint256 soldOutToken = imprints.addImprintType(
            creator, "ipfs://QmSoldOut", 1, 1e6, ROYALTY_BPS, keccak256("soldout2"), 1
        );
        imprints.adminMint(buyer, soldOutToken, 1, "");

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = soldOutToken;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        vm.prank(buyer2);
        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.CollectionSoldOut.selector, collectionId));
        imprints.mintFromCollection(collectionId, 1);
    }

    function test_mintFromCollection_zeroAmount_reverts() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        vm.prank(buyer);
        vm.expectRevert(MemonexImprints.InvalidAmount.selector);
        imprints.mintFromCollection(collectionId, 0);
    }

    function test_mintFromCollection_invalidCollection_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IMemonexImprints.InvalidCollection.selector, 777));
        imprints.mintFromCollection(777, 1);
    }

    // ══════════════════════════════════════════════════════════════
    // collectionOnly protection
    // ══════════════════════════════════════════════════════════════

    function test_collectionOnly_defaultTrue() public {
        uint256 tid = imprints.addImprintType(creator, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, 0);
        IMemonexImprints.ImprintType memory t = imprints.getImprintType(tid);
        assertTrue(t.collectionOnly);
    }

    function test_collectionOnly_purchaseReverts() public {
        uint256 tid = imprints.addImprintType(creator, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, 0);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MemonexImprints.TokenCollectionOnly.selector, tid));
        imprints.purchase(tid, 1);
    }

    function test_collectionOnly_mintFromCollectionStillWorks() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);
        // t1 is collectionOnly=true by default — mintFromCollection should still work

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 2e6, tokenIds, weights);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId);

        assertEq(imprints.balanceOf(buyer, t1), 1);
    }

    function test_collectionOnly_adminMintStillWorks() public {
        uint256 tid = _addDefault();
        // collectionOnly=true by default — adminMint should still work
        imprints.adminMint(buyer, tid, 1, "");
        assertEq(imprints.balanceOf(buyer, tid), 1);
    }

    function test_collectionOnly_uriHiddenWhenUnminted() public {
        uint256 tid = imprints.addImprintType(creator, META_URI, MAX_SUPPLY, PRICE, ROYALTY_BPS, CONTENT_HASH, 0);

        // collectionOnly=true, minted=0 → empty uri
        assertEq(imprints.uri(tid), "");
    }

    function test_collectionOnly_uriRevealedAfterMint() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        // Before any mints, uri is hidden
        assertEq(imprints.uri(t1), "");

        // Mint via collection
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 2e6, tokenIds, weights);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId);

        // After mint, uri is revealed
        string memory revealed = imprints.uri(t1);
        assertGt(bytes(revealed).length, 0);
    }

    function test_collectionOnly_nonexistentTokenReturnsEmpty() public {
        // Non-existent token: collectionOnly defaults to false, minted defaults to 0
        // ERC1155URIStorage will just return "" for non-existent tokens
        assertEq(imprints.uri(999), "");
    }

    // ══════════════════════════════════════════════════════════════
    // Allowlist + claim limits + free mint
    // ══════════════════════════════════════════════════════════════

    function test_addToAllowlist_ownerBatchAndRemove() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        address[] memory wallets = new address[](2);
        wallets[0] = buyer;
        wallets[1] = buyer2;

        vm.expectEmit(true, true, false, true, address(imprints));
        emit AllowlistUpdated(collectionId, buyer, true);
        vm.expectEmit(true, true, false, true, address(imprints));
        emit AllowlistUpdated(collectionId, buyer2, true);
        imprints.addToAllowlist(collectionId, wallets);

        assertTrue(imprints.allowlisted(collectionId, buyer));
        assertTrue(imprints.allowlisted(collectionId, buyer2));

        vm.expectEmit(true, true, false, true, address(imprints));
        emit AllowlistUpdated(collectionId, buyer, false);
        imprints.removeFromAllowlist(collectionId, wallets);

        assertFalse(imprints.allowlisted(collectionId, buyer));
        assertFalse(imprints.allowlisted(collectionId, buyer2));
    }

    function test_addToAllowlist_creatorCanBatchAdd() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);
        imprints.setCollectionCreatorAuthorization(collectionCurator, true);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(collectionCurator, 1e6, tokenIds, weights);

        address[] memory wallets = new address[](2);
        wallets[0] = buyer;
        wallets[1] = buyer2;

        vm.prank(collectionCurator);
        imprints.addToAllowlist(collectionId, wallets);

        assertTrue(imprints.allowlisted(collectionId, buyer));
        assertTrue(imprints.allowlisted(collectionId, buyer2));
    }

    function test_allowlistAdminFunctions_nonAdminRevert() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        address[] memory wallets = new address[](1);
        wallets[0] = buyer;

        vm.startPrank(buyer2);
        vm.expectRevert(MemonexImprints.NotCollectionAdmin.selector);
        imprints.addToAllowlist(collectionId, wallets);

        vm.expectRevert(MemonexImprints.NotCollectionAdmin.selector);
        imprints.removeFromAllowlist(collectionId, wallets);

        vm.expectRevert(MemonexImprints.NotCollectionAdmin.selector);
        imprints.setAllowlistRequired(collectionId, true);

        vm.expectRevert(MemonexImprints.NotCollectionAdmin.selector);
        imprints.setClaimLimit(collectionId, 1);
        vm.stopPrank();
    }

    function test_setAllowlistRequired_toggle() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        vm.expectEmit(true, false, false, true, address(imprints));
        emit AllowlistRequirementChanged(collectionId, true);
        imprints.setAllowlistRequired(collectionId, true);
        assertTrue(imprints.allowlistRequired(collectionId));

        vm.expectEmit(true, false, false, true, address(imprints));
        emit AllowlistRequirementChanged(collectionId, false);
        imprints.setAllowlistRequired(collectionId, false);
        assertFalse(imprints.allowlistRequired(collectionId));
    }

    function test_mintFromCollection_allowlistRequired() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);
        imprints.setAllowlistRequired(collectionId, true);

        vm.prank(buyer);
        vm.expectRevert(IMemonexImprints.NotAllowlisted.selector);
        imprints.mintFromCollection(collectionId, 1);

        address[] memory wallets = new address[](1);
        wallets[0] = buyer;
        imprints.addToAllowlist(collectionId, wallets);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId, 1);

        assertEq(imprints.balanceOf(buyer, t1), 1);
        assertEq(imprints.claimedCount(collectionId, buyer), 1);
    }

    function test_mintFromCollection_allowlistOff_anyoneCanMint() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId, 1);

        vm.prank(buyer2);
        imprints.mintFromCollection(collectionId, 1);

        assertEq(imprints.balanceOf(buyer, t1), 1);
        assertEq(imprints.balanceOf(buyer2, t1), 1);
    }

    function test_createCollection_zeroMintPrice_allowed() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 0, tokenIds, weights);
        IMemonexImprints.Collection memory collection = imprints.getCollection(collectionId);
        assertEq(collection.mintPrice, 0);
    }

    function test_mintFromCollection_freeMint_noUsdcTransfers() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);
        imprints.setCollectionCreatorAuthorization(collectionCurator, true);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(collectionCurator, 0, tokenIds, weights);

        uint256 buyerBefore = usdc.balanceOf(buyer);
        uint256 treasuryBefore = usdc.balanceOf(treasury);
        uint256 curatorBefore = usdc.balanceOf(collectionCurator);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId, 2);

        assertEq(imprints.balanceOf(buyer, t1), 2);
        assertEq(usdc.balanceOf(buyer), buyerBefore);
        assertEq(usdc.balanceOf(treasury), treasuryBefore);
        assertEq(usdc.balanceOf(collectionCurator), curatorBefore);
    }

    function test_setClaimLimit_andEnforce() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        vm.expectEmit(true, false, false, true, address(imprints));
        emit ClaimLimitChanged(collectionId, 2);
        imprints.setClaimLimit(collectionId, 2);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId, 1);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId, 1);

        assertEq(imprints.claimedCount(collectionId, buyer), 2);

        vm.prank(buyer);
        vm.expectRevert(IMemonexImprints.ClaimLimitExceeded.selector);
        imprints.mintFromCollection(collectionId, 1);
    }

    function test_claimLimit_zeroMeansUnlimited() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);
        imprints.setClaimLimit(collectionId, 0);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId, 3);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId, 4);

        assertEq(imprints.claimedCount(collectionId, buyer), 7);
    }

    function test_allowlistBatch_edgeCases() public {
        uint256 t1 = _addImprint(creator, 100, 1e6);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = t1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        // Empty batch should be a no-op
        address[] memory emptyWallets = new address[](0);
        imprints.addToAllowlist(collectionId, emptyWallets);
        imprints.removeFromAllowlist(collectionId, emptyWallets);

        // Duplicate addresses should remain idempotent
        address[] memory duplicates = new address[](2);
        duplicates[0] = buyer;
        duplicates[1] = buyer;
        imprints.addToAllowlist(collectionId, duplicates);
        assertTrue(imprints.allowlisted(collectionId, buyer));

        // Removing non-existent entry should be a no-op
        address[] memory notListed = new address[](1);
        notListed[0] = buyer2;
        imprints.removeFromAllowlist(collectionId, notListed);
        assertFalse(imprints.allowlisted(collectionId, buyer2));
    }

    function test_blindMint_distributionSanity() public {
        uint256 common = _addImprint(creator, 5000, 1e6);
        uint256 uncommon = _addImprint(creator, 5000, 1e6);
        uint256 rare = _addImprint(creator, 5000, 1e6);
        uint256 legendary = _addImprint(creator, 5000, 1e6);
        uint256 mythic = _addImprint(creator, 5000, 1e6);

        uint256[] memory tokenIds = new uint256[](5);
        tokenIds[0] = common;
        tokenIds[1] = uncommon;
        tokenIds[2] = rare;
        tokenIds[3] = legendary;
        tokenIds[4] = mythic;

        uint256[] memory weights = new uint256[](5);
        weights[0] = 50;
        weights[1] = 25;
        weights[2] = 15;
        weights[3] = 8;
        weights[4] = 2;

        uint256 collectionId = _createCollectionAs(address(this), 1e6, tokenIds, weights);

        vm.prank(buyer);
        imprints.mintFromCollection(collectionId, 900);

        uint256 commonCount = imprints.balanceOf(buyer, common);
        uint256 uncommonCount = imprints.balanceOf(buyer, uncommon);
        uint256 rareCount = imprints.balanceOf(buyer, rare);
        uint256 legendaryCount = imprints.balanceOf(buyer, legendary);
        uint256 mythicCount = imprints.balanceOf(buyer, mythic);

        // Statistical sanity assertions (non-flaky / order-based)
        assertGt(commonCount, uncommonCount);
        assertGt(uncommonCount, rareCount);
        assertGt(rareCount, legendaryCount);
        assertGt(legendaryCount, mythicCount);
        assertEq(commonCount + uncommonCount + rareCount + legendaryCount + mythicCount, 900);
    }
}
