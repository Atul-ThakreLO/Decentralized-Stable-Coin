// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DecentralizedStablecoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    address[] usersWithDepositedCollateral;

    constructor(DecentralizedStablecoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;
        address[] memory collateralTokens = dscEngine.getTokenAddresses();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        /**
         * Here we are minting some token and then approve it. This is because sender don't have enough
         *        token to approve hence mint first then approve.
         * In production this is done in frontend, we will have some token, we just need to approve, if
         *        we don't have, then need to grab some.
         */
        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amountCollateral);
        collateralToken.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();

        usersWithDepositedCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        uint256 maxAmountToRedeem = dscEngine.getCollateralBalanceOfUser(address(collateralToken), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxAmountToRedeem);
        // if(amountCollateral == 0) return;
        // or
        vm.assume(amountCollateral != 0);
        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(collateralToken), amountCollateral);
        // vm.stopPrank();
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        if (usersWithDepositedCollateral.length == 0) return;
        address sender = usersWithDepositedCollateral[addressSeed % usersWithDepositedCollateral.length];
        vm.startPrank(sender);
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine.getAccountInformation(sender);
        int256 maxAmountToMint = (int256(collateralValueInUSD) / 2) - int256(totalDSCMinted);
        if (maxAmountToMint <= 0) {
            vm.stopPrank();
            return;
        }
        amount = bound(amount, 0, uint256(maxAmountToMint));
        if (amount == 0) {
            vm.stopPrank();
            return;
        }
        dscEngine.mintDSC(amount);
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
