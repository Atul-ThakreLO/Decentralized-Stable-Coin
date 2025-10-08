// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {Handler} from "./Handler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariants is StdInvariant, Test {
    DSCEngine dscEngine;
    DeployDSC deployer;
    DecentralizedStablecoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        Handler handler = new Handler(dsc, dscEngine);
        (,, weth, wbtc,) = config.activeNetworkConfig();
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupplyDollars() public view {
        uint256 totalSupply = dsc.totalSupply();

        uint256 totalWETHDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalBTCDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUSDValue(weth, totalWETHDeposited);
        uint256 wbtcValue = dscEngine.getUSDValue(wbtc, totalBTCDeposited);

        console.log("weth:", wethValue);
        console.log("wbtc:", wbtcValue);
        console.log("total supply:", totalSupply);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
