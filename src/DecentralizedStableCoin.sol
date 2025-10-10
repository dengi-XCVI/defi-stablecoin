// SPDX-License-Identifier: MIT

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

/**
 * @title DecentralizedStableCoin
 * @author Dennis Gianassi
 * Relative stability: pegged to USD
 * Collateral: Exogenous assets
 * Minting: Algorithmic
 * 
 * This contract is meant to be governed by DSCEngine. This contract is the ERC20 implementation of the stablecoin.
 */

import {ERC20Burnable, ERC20} from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

contract DecentralizedStableCoin is ERC20Burnable, Ownable {

    error DecentralisedStableCoin__BurnAmountExceedsBalance();
    error DecentralisedStableCoin__MustBeMoreThanZero();
    error DecentralisedStableCoin__NonZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount > balance) {
            revert DecentralisedStableCoin__BurnAmountExceedsBalance();
        }
        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin__NonZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
} 