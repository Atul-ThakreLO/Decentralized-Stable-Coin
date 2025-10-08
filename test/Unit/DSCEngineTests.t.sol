//  SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTests is Test {
    DeployDSC deployer;
    DecentralizedStablecoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;

    uint256 amountToMint = 100 ether;
    address wethPriceFeed;
    address wbtcPriceFedd;
    address weth;

    address USER = makeAddr("user");
    uint256 constant ACCOUNT_COLLATERAL = 10 ether;
    uint256 constant MINT_AMOUNT = 3 ether;
    uint256 constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wethPriceFeed, wbtcPriceFedd, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ////////////////////////////////////////////////////////////
    //////////////////// Constructor Tests /////////////////////
    ////////////////////////////////////////////////////////////

    address[] private tokenAddresses;
    address[] private priceFeedAddresses;

    function testRevertIfTokenLengthNotEqualPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethPriceFeed);
        priceFeedAddresses.push(wbtcPriceFedd);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesMustEqualPriceFeedAddresses.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////////////////////////////////////////////
    //////////////////////// Price Test ////////////////////////
    ////////////////////////////////////////////////////////////

    function testGetTokenAmountFromUSD() public view {
        uint256 usdAmount = 100 ether;
        /**
         * We set the price of $/ETH to 2000ether in HelperConfig
         * Hence for 100ether  100/2000 = 0.05
         */
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testGetUSDValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUSD = 30000e18;

        uint256 actualUSD = dscEngine.getUSDValue(weth, ethAmount);

        assertEq(expectedUSD, actualUSD);
    }

    ////////////////////////////////////////////////////////////
    //////////////// Deposite Collateral Tests /////////////////
    ////////////////////////////////////////////////////////////

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), ACCOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, ACCOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testRevertIfTokenNotAllowed() public {
        vm.startPrank(USER);
        ERC20Mock prankToken = new ERC20Mock("PRA", "PRA", USER, ACCOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(prankToken), ACCOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        /**
         * In real the approve here is actually done by the user, like we do on metamask before transaction.
         * Refer web3 fullstack - Tsender may be.
         */
        ERC20Mock(weth).approve(address(dsc), ACCOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanDepositedCollateralAndGetInfo() public depositCollateral {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine.getAccountInformation(USER);
        uint256 expectedTotalDSCMinted = 0;
        uint256 expectedCollateral = dscEngine.getTokenAmountFromUSD(weth, collateralValueInUSD);
        assertEq(totalDSCMinted, expectedTotalDSCMinted);
        assertEq(ACCOUNT_COLLATERAL, expectedCollateral);
    }

    ////////////////////////////////////////////////////////////
    ////////////////////// Mint DSC tests //////////////////////
    ////////////////////////////////////////////////////////////

    modifier mintDSC() {
        (, int256 price,,,) = MockV3Aggregator(wethPriceFeed).latestRoundData();
        amountToMint = (3 ether * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();
        vm.startPrank(USER);
        dscEngine.mintDSC(amountToMint);
        vm.stopPrank();
        _;
    }

    function testRevertIfHelathFactorBrokenForMintingDSC() public depositCollateral {
        (, int256 price,,,) = MockV3Aggregator(wethPriceFeed).latestRoundData();
        amountToMint =
            (ACCOUNT_COLLATERAL * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();
        vm.startPrank(USER);
        uint256 healthFactor =
            dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUSDValue(weth, ACCOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BrokesHealthFactor.selector, healthFactor));
        dscEngine.mintDSC(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDSC() public depositCollateral mintDSC {
        vm.startPrank(USER);
        uint256 expectedAmount = IERC20(dsc).balanceOf(USER);
        assertEq(expectedAmount, amountToMint);
        vm.stopPrank();
    }
    // Simpler version
    // function testCanMintDsc() public depositCollateral {
    //     vm.prank(user);
    //     dsce.mintDsc(amountToMint);

    //     uint256 userBalance = dsc.balanceOf(user);
    //     assertEq(userBalance, amountToMint);
    // }

    ////////////////////////////////////////////////////////////
    ///////////////// Redeem Collateral Tests //////////////////
    ////////////////////////////////////////////////////////////

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        /**
         * In real the approve here is actually done by the user, like we do on metamask before transaction.
         * Refer web3 fullstack - Tsender may be.
         */
        ERC20Mock(weth).approve(address(dsc), ACCOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemColateral() public depositCollateral {
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, ACCOUNT_COLLATERAL);
        uint256 expectedCollateralBalance = 0;
        (, uint256 collateralValueInUSD) = dscEngine.getAccountInformation(USER);
        uint256 actualCollateralBalance = dscEngine.getTokenAmountFromUSD(weth, collateralValueInUSD);
        vm.stopPrank();
        assertEq(expectedCollateralBalance, actualCollateralBalance);
    }

    ////////////////////////////////////////////////////////////
    ////////////////////// Burn DSC Tests //////////////////////
    ////////////////////////////////////////////////////////////

    function testCanBurnDSC() public depositCollateral mintDSC {
        vm.startPrank(USER);
        // Approve the DSC engine to spend the user's DSC tokens for burning
        IERC20(dsc).approve(address(dscEngine), amountToMint);
        dscEngine.burnDSC(amountToMint);
        uint256 expectedAmount = IERC20(dsc).balanceOf(USER);
        assertEq(expectedAmount, 0);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////////////
    ///////////////////// Lquidation tests /////////////////////
    ////////////////////////////////////////////////////////////

    function testRevertHealthFactorNotBroken() public depositCollateral mintDSC {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotBrokenHealthFactor.selector);
        dscEngine.liquidate(weth, USER, ACCOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testLiquidation() public depositCollateral {}
}
