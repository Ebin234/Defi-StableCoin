// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

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

contract DSCEngine{

    function depositCollateralAndMintDSC() external {}

    function depositCollateral() external{}

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function mintDsc() external{}

    function burnDsc() external{}

    function liquidate() external{}

    function getHealthFactor() external{}
}