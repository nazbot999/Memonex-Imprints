// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {MemonexImprints} from "../contracts/MemonexImprints.sol";

/// @notice Deployment script for Monad testnet.
/// @dev Usage:
///      export PATH="$HOME/.foundry/bin:$PATH"
///      forge script script/Deploy.s.sol:Deploy --rpc-url https://testnet-rpc.monad.xyz --broadcast
///
/// Env:
/// - PRIVATE_KEY (required)
/// - USDC_ADDRESS (optional, defaults to Monad testnet USDC)
/// - TREASURY_ADDRESS (optional, defaults to deployer)
/// - PLATFORM_FEE_BPS (optional, default 500)
/// - SECONDARY_FEE_BPS (optional, default 250)
contract Deploy is Script {
    address internal constant MONAD_TESTNET_USDC = 0x534b2f3A21130d7a60830c2Df862319e593943A3;

    function run() external returns (MemonexImprints deployed) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        address usdcAddress = vm.envOr("USDC_ADDRESS", MONAD_TESTNET_USDC);
        address treasuryAddress = vm.envOr("TREASURY_ADDRESS", deployer);
        uint96 platformFee = uint96(vm.envOr("PLATFORM_FEE_BPS", uint256(500)));
        uint96 secondaryFee = uint96(vm.envOr("SECONDARY_FEE_BPS", uint256(250)));

        vm.startBroadcast(privateKey);

        deployed = new MemonexImprints(usdcAddress, treasuryAddress, platformFee, secondaryFee);

        console.log("MemonexImprints deployed:", address(deployed));
        console.log("USDC:", usdcAddress);
        console.log("Treasury:", treasuryAddress);
        console.log("Platform fee bps:", platformFee);
        console.log("Secondary fee bps:", secondaryFee);

        vm.stopBroadcast();
    }
}
