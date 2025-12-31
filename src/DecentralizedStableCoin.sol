// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable,ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * title: DecentralizedStableCoin
 * author: Ebin Yesudas.
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * 
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin system.
 */

contract DecentralizedStableCoin is ERC20Burnable,Ownable{
    /** ERRORS */
    error DecentralizedStableCoin__BurnAmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsUserBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    /** FUNCTIONS */

    constructor(address initialOwner) ERC20("DecentralizedStableCoin","DSC") Ownable(initialOwner){}

    function burn(uint256 _amount) public override onlyOwner{
        uint256 userBalance = balanceOf(msg.sender);
        if(_amount <= 0){
            revert DecentralizedStableCoin__BurnAmountMustBeMoreThanZero();
        }
        if(userBalance < _amount){
            revert DecentralizedStableCoin__BurnAmountExceedsUserBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to,uint256 _amount) external onlyOwner returns(bool){
        if(_to == address(0)){
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if(_amount <= 0){
            revert DecentralizedStableCoin__BurnAmountMustBeMoreThanZero();
        }

        _mint(_to,_amount);
        return true;
    }
}