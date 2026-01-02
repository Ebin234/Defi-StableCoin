// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    DecentralizedStableCoin private immutable i_dsc;

    mapping(address tokenAddress => address priceFeed) private s_priceFeeds;
    mapping(address users => mapping(address token => uint256 amount))
        private s_collateralDeposited;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

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

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesArrayAndPriceFeedAddressesArrayMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositCollateralAndMintDSC() external {}

    /**
     *
     * @param tokenCollateralAddress: The ERC20 address of the collateral you're depositing.
     * @param collateralAmount: The amount of collateral you are depositing.
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 collateralAmount
    )
        external
        amountMoreThanZero(collateralAmount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += collateralAmount;

        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            collateralAmount
        );

        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external {}
}
