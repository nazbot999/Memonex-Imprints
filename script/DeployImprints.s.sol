// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {MemonexImprints} from "../contracts/MemonexImprints.sol";
import {MockUSDC} from "../contracts/test/MockUSDC.sol";

/// @notice Foundry deploy script for MemonexImprints.
/// @dev Usage:
///   forge script script/DeployImprints.s.sol:DeployImprints --rpc-url $RPC_URL --broadcast
/// Env:
///   PRIVATE_KEY (required)
///   USDC_ADDRESS (optional — deploys MockUSDC if DEPLOY_MOCK_USDC=true)
///   TREASURY_ADDRESS (optional — defaults to deployer)
///   PLATFORM_FEE_BPS (optional — default 250 = 2.5%)
///   SECONDARY_FEE_BPS (optional — default 250 = 2.5%)
///   DEPLOY_MOCK_USDC (optional — set "true" to deploy mock)
contract DeployImprints is Script {
    // Monad testnet defaults
    address internal constant MONAD_TESTNET_USDC = 0x534b2f3A21130d7a60830c2Df862319e593943A3;

    function run() external returns (MemonexImprints market, address usdcAddr) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        bool deployMock = vm.envOr("DEPLOY_MOCK_USDC", false);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        uint96 platformFeeBps = uint96(vm.envOr("PLATFORM_FEE_BPS", uint256(250)));
        uint96 secondaryFeeBps = uint96(vm.envOr("SECONDARY_FEE_BPS", uint256(250)));

        vm.startBroadcast(pk);

        if (deployMock) {
            MockUSDC mockUsdc = new MockUSDC();
            usdcAddr = address(mockUsdc);
            console.log("MockUSDC deployed:", usdcAddr);
        } else {
            usdcAddr = vm.envOr("USDC_ADDRESS", MONAD_TESTNET_USDC);
        }

        market = new MemonexImprints(usdcAddr, treasury, platformFeeBps, secondaryFeeBps);
        console.log("MemonexImprints deployed:", address(market));
        console.log("  USDC:", usdcAddr);
        console.log("  Treasury:", treasury);
        console.log("  Platform fee:", platformFeeBps, "bps");
        console.log("  Secondary fee:", secondaryFeeBps, "bps");

        vm.stopBroadcast();
    }
}
