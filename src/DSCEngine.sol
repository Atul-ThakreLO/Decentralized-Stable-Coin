// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {DecentralizedStablecoin} from "./DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSC Engine
 * @author Atul Thakre
 * @notice 
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////////////////////////////////////////////////
    ////////////////////////// Errors //////////////////////////
    ////////////////////////////////////////////////////////////

    error DSCEngine__AmountMustBeMoreThanZero();
    error DSCEngine__TokenAddressesMustEqualPriceFeedAddresses();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BrokesHealthFactor(uint256 healthFactor);
    error DSCEngine__MintingFailed();
    error DSCEngine__NotBrokenHealthFactor();
    error DSCEngine__HealthFactorNotImporoved();
    error DSCEngine__LiquidatorHasNotEnoughDSC(uint256 liquidatorBalance);
    error DSCEngine__InsufficientCollateral();

    ////////////////////////////////////////////////////////////
    ////////////////////////// Types ///////////////////////////
    ////////////////////////////////////////////////////////////

    using OracleLib for AggregatorV3Interface;

    ////////////////////////////////////////////////////////////
    ///////////////////// State Variables //////////////////////
    ////////////////////////////////////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% Over Collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10%
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeeds) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStablecoin private immutable i_dsc;

    ////////////////////////////////////////////////////////////
    ////////////////////////// Events //////////////////////////
    ////////////////////////////////////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event DSCMinted(address indexed user, uint256 indexed amountToMint);
    event DSCBurned(address indexed onBehalfOf, address indexed from, uint256 indexed amountToBurn);
    event Liquidated(address indexed onBehalfOf, address indexed from, uint256 amountRedeemed);

    ////////////////////////////////////////////////////////////
    //////////////////////// Modifiers /////////////////////////
    ////////////////////////////////////////////////////////////

    modifier amountMoreThanZero(uint256 amountCollateral) {
        if (amountCollateral == 0) {
            revert DSCEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier isTokenAllowed(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ////////////////////////////////////////////////////////////
    //////////////////////// Functions /////////////////////////
    ////////////////////////////////////////////////////////////

    constructor(address[] memory tokenAddressess, address[] memory priceFeedsAddresses, address dscAddress) {
        if (tokenAddressess.length != priceFeedsAddresses.length) {
            revert DSCEngine__TokenAddressesMustEqualPriceFeedAddresses();
        }
        for (uint256 i = 0; i < tokenAddressess.length; i++) {
            s_priceFeeds[tokenAddressess[i]] = priceFeedsAddresses[i];
            s_collateralTokens.push(tokenAddressess[i]);
        }
        i_dsc = DecentralizedStablecoin(dscAddress);
    }

    ////////////////////////////////////////////////////////////
    ////////////////////// Main Functions //////////////////////
    ////////////////////////////////////////////////////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposite as a collateral
     * @param amountCollateral The amount of collateral to deposite
     * @param amountDSCToMint The amount of DSC to mint from collateral
     * @notice This Function deposite collateral and mint the dsc.
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /**
     * @notice follows CEI - check, effects, interactions.
     * @param tokenCollateralAddress The address of the token to deposite as a collateral
     * @param amountCollateral The amount of collateral to deposited
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        amountMoreThanZero(amountCollateral)
        isTokenAllowed(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The address of the token
     * @param amountCollateral The amount of the collateral to be redeem.
     * @param amountToBurnDSC The amount of DSC to burn.
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBurnDSC)
        external
    {
        _burnDSC(msg.sender, msg.sender, amountToBurnDSC);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        amountMoreThanZero(amountCollateral)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI.
     * @param amountDSCToMint Amount of DSC to mint.
     * @notice They must have more collateral value than the minimum threshold.
     */
    function mintDSC(uint256 amountDSCToMint) public amountMoreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintingFailed();
        }
        emit DSCMinted(msg.sender, amountDSCToMint);
    }

    function burnDSC(uint256 amount) public amountMoreThanZero(amount) {
        _burnDSC(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param collateralAddress : The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user : The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover : The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice : You can partially liquidate a user.
     * @notice : You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice : This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice : A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateralAddress, address user, uint256 debtToCover) external {
        if (i_dsc.balanceOf(msg.sender) < debtToCover) {
            revert DSCEngine__LiquidatorHasNotEnoughDSC(i_dsc.balanceOf(msg.sender));
        }

        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__NotBrokenHealthFactor();
        }
        uint256 userCollateralAmount = s_collateralDeposited[user][collateralAddress];
        uint256 userCollateralAmountInUSD = getUSDValue(collateralAddress, userCollateralAmount);

        /**
         * Formula: maxDebt = (userCollateralAmountInUSD * 100) / (100 + bonus)
         * OR
         * maxDebt = (bonus/100) * userCollateralAmountInUSD - userCollateralAmountInUSD
         * simply (bonus/100) * userCollateralAmountInUSD means x% of userCollateralAmountInUSD
         */
        uint256 maxDebtThatCanBeCovered =
            (userCollateralAmountInUSD * LIQUIDATION_PRECISION) / (LIQUIDATION_PRECISION + LIQUIDATION_BONUS);

        uint256 actualDebtToCover = debtToCover > maxDebtThatCanBeCovered 
        ? maxDebtThatCanBeCovered 
        : debtToCover;

        /**
         * So we want to burn their DSC debt
         * And take their collateral
         * Undercollateralized --> User has $140 and $100 DSC, Because user must need to be 200% collateralized
         *      The user will be collateralized if he has $200 or more, then the user is collateralized
         * So we have to pay UpTo $100 DSC
         * In return we will get the collaterl plus the bonus.
         * Hence caluculate ETH for $100 DSC
         */
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateralAddress, actualDebtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeeem = bonusCollateral + tokenAmountFromDebtCovered;

        _redeemCollateral(collateralAddress, totalCollateralToRedeeem, user, msg.sender);
        _burnDSC(user, msg.sender, actualDebtToCover);

        // Check for healthFactor, is it is Improved ?

        uint256 endingHealthFactor = _healthFactor(user);

        if (startingHealthFactor <= endingHealthFactor) {
            revert DSCEngine__HealthFactorNotImporoved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
        emit Liquidated(user, msg.sender, totalCollateralToRedeeem);
    }

    ////////////////////////////////////////////////////////////
    ///////////// Private and internal Functions ///////////////
    ////////////////////////////////////////////////////////////

    function _burnDSC(address onBehalfOf, address dscFrom, uint256 amountDSCToBurn) private {
        s_DSCMinted[onBehalfOf] -= amountDSCToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDSCToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDSCToBurn);
        emit DSCBurned(onBehalfOf, dscFrom, amountDSCToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        if (s_collateralDeposited[from][tokenCollateralAddress] < amountCollateral) {
            revert DSCEngine__InsufficientCollateral();
        }
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation user is ?
     * If user goes below 1, they will get liquidet.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BrokesHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUSD)
        private
        pure
        returns (uint256)
    {
        /**
         * If no DSC is minted, return a very high health factor (user is safe)
         * Hence, use ->
         * @note type(uint256).max is a Solidity built-in that returns the maximum possible value that can be stored in a uint256 variable.
         * Value: 2^256 - 1
         */
        if (totalDSCMinted == 0) {
            return type(uint256).max;
        }

        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
        // return (collateralAdjustedForThreshold) / totalDSCMinted;
    }

    ////////////////////////////////////////////////////////////
    //////////// Public and External View Functios /////////////
    ////////////////////////////////////////////////////////////

    function getTokenAmountFromUSD(address token, uint256 usdAmountInWEI) public view returns (uint256) {
        /**
         *                     $/ETH
         *                       |
         * Consider price - $2000/ETH so how much is $1000 --> 1000/2000 = 0.5
         */
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        /**
         * $100e18 USD Debt
         * 1 ETH = 2000 USD
         * The returned value from Chainlink (AggregatorV3Interface) will be 2000 * 1e8
         * Most USD pairs have 8 decimals, so we will just pretend they all do
         *
         * return (1000e18 * 1e18 / 2000e8 * 1e10 ) = 0.5e18
         */
        return ((usdAmountInWEI * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getDepositedCollateral(address user, address tokenAddress) public view returns (uint256) {
        return s_collateralDeposited[user][tokenAddress];
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        (totalDSCMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        public
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAdditionalFeedPrecision() public pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() public pure returns (uint256) {
        return PRECISION;
    }

    function getTokenAddresses() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address token, address user) public view returns (uint256) {
        return s_collateralDeposited[token][user];
    }
}
