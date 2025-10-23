// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we interact with our system

pragma solidity ^0.8.19;

import {Test,console} from 'forge-std/Test.sol';
import {DSCEngine} from '../../src/DSCEngine.sol';
import {DecentralizedStableCoin} from '../../src/DecentralizedStableCoin.sol';
import {ERC20Mock} from '@openzeppelin/contracts/mocks/token/ERC20Mock.sol';

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintIsCalled = 0;  
    address[] public usersWithCollateralDeposited;
    uint256 MINIMUM_HEALTH_FACTOR = 1e18; // 1 * 10^18

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

    }

    function mintDsc(uint256 amountDsc, uint256 seedAddress) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }   
        address sender = usersWithCollateralDeposited[seedAddress % usersWithCollateralDeposited.length];
        int256 maxMintableDsc = dscEngine.getMaxMintableDsc(sender);
        if (maxMintableDsc <= 0) {
            return;
        }
        amountDsc = bound(amountDsc ,0, uint256(maxMintableDsc));  
        if (amountDsc == 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDsc(amountDsc);   
        vm.stopPrank();
        timesMintIsCalled += 1;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        console.log("Depositing collateral:", amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);   
        vm.stopPrank();
        // double push
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral, uint256 seedAddress) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        address user = usersWithCollateralDeposited[seedAddress % usersWithCollateralDeposited.length];
        uint256 maxRedeemableCollateral = dscEngine.getCollateralBalanceOfUser(user, address(collateral));
        
        amountCollateral = bound(amountCollateral, 0, maxRedeemableCollateral);
        if (amountCollateral == 0) {
            vm.stopPrank();
            return;
        }
        vm.startPrank(user);
        // Try catch to avoid health factor reverts on redeem collateral
        try dscEngine.redeemCollateral(address(collateral), amountCollateral) {} catch {
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
    }

    //// Helper functions///////////

    function _getCollateralFromSeed(uint256 collateralSeed) internal view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth; // WETH
        } else {
            return wbtc; // WBTC
        }
    }

}
