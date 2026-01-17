// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Ebin Yesudas
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1token == $1 peg at all time.
 * This is a stablecoin with the properties :
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only wETH and wBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of collateral < the $ backed value of all the DSC.
 *
 *
 * @notice This contract is the core of the Decentralized StableCoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system.
 *
 */

contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__AmountMustBeMoreThanZero();
    error DSCEngine__TokenAddressesArrayAndPriceFeedAddressesArrayMustBeSameLength();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHelthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    DecentralizedStableCoin private immutable i_dsc;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address tokenAddress => address priceFeed) private s_priceFeeds;
    mapping(address users => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event collateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier amountMoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesArrayAndPriceFeedAddressesArrayMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     *
     * @param tokenCollateralAddress: The address of the token to deposit as collateral.
     * @param collateralAmount: The amount of collateral to deposit.
     * @param amountDscToMint: The amount of DecentralizedStableCoin to mint.
     * @notice This function will deposit your collateral and mint DSC in one transaction.
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 collateralAmount,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDsc(amountDscToMint);
    }

    /**
     *
     * @param tokenCollateralAddress: The ERC20 address of the collateral you're depositing.
     * @param collateralAmount: The amount of collateral you are depositing.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        amountMoreThanZero(collateralAmount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += collateralAmount;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, collateralAmount);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param burnAmount: Amount of Dsc to burn.
     * @param tokenCollateralAddress: The collateral address to redeem.
     * @param collateralAmount: Amount of collateral to redeem.
     * @notice This function burns DSC and redeem underlying collateral in one transaction.
     */
    function redeemCollateralForDSC(uint256 burnAmount, address tokenCollateralAddress, uint256 collateralAmount)
        external
    {
        burnDsc(burnAmount);
        redeemCollateral(tokenCollateralAddress, collateralAmount);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        amountMoreThanZero(collateralAmount)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= collateralAmount;
        emit collateralRedeemed(msg.sender, tokenCollateralAddress, collateralAmount);

        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     *
     * @param amountDscToMint : The amount of Dsc you want to mint.
     * @notice : You can only mint Dsc if you have enough collateral
     */
    function mintDsc(uint256 amountDscToMint) public amountMoreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     *
     * @param burnAmount: The amount of Dsc you want to burn.
     */
    function burnDsc(uint256 burnAmount) public amountMoreThanZero(burnAmount) {
        s_DSCMinted[msg.sender] -= burnAmount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), burnAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(burnAmount);
    }

    /**
     *
     * @param user : The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR.
     * @param tokenCollateralAddress : The ERC20 token address of the collateral.
     * This is the collateral that you are going to take from the user who is insolvent.
     * In return you have to burn your DSC to pay off their debt. But you don't pay off your own.
     * @param debtToCover : The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice You can partially liquidate a user.
     * @notice You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol was only 100% overcollateralized, we wouldn't be able to liquidate anyone.
     *
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address user, address tokenCollateralAddress, uint256 debtToCover)
        external
        amountMoreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered + bonusCollateral;
    }

    function getHealthFactor() external view {}

    /*//////////////////////////////////////////////////////////////
                    PUBLIC & EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getTokenAmountFromUsd(address tokenCollateralAddress, uint256 usdAmountInWei)
        public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 collateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            collateralValueInUsd += getUsdValue(token, amount);
        }
        return collateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                    PRIVATE & INTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHelthFactor(userHealthFactor);
        }
    }

    /**
     *
     * @param user : Address of the user.
     * Returns how close to liquidate a user is
     * If a user goes below 1, Then they can be liquidated.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformations(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformations(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
}
