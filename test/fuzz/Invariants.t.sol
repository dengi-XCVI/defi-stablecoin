// SPDX-License-Identifier: MIT

// Have our invariants or properties that have to hold

// What are our invariants?
// 1. The total supply of DSC should never exceed the total value of collateral in the system
// 2. Getters should never revert -> Usually in every protocol

pragma solidity ^0.8.19;

import {Test, console} from 'forge-std/Test.sol';
import {StdInvariant} from 'forge-std/StdInvariant.sol';
import {DSCEngine} from '../../src/DSCEngine.sol';
import {DecentralizedStableCoin} from '../../src/DecentralizedStableCoin.sol';
import {DeployDSC} from '../../script/DeployDSC.s.sol';
import {HelperConfig} from '../../script/HelperConfig.s.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Handler} from './Handler.t.sol';

contract InvariantsTest is StdInvariant ,Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    DeployDSC deployer;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() public {
        // Set up code if needed
        // targetContract(address_of_the_contract_to_test);
        deployer = new DeployDSC();
        (dsc,dscEngine,config) = deployer.run();
        (,,weth,wbtc,) = config.getActiveNetworkConfig();

        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
        
    }
    // Handler


    function invariant_DscTotalSupplyLessThanCollateral() public view {
        // totalSupply <= totalCollateralValue
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
        uint256 totalCollateralValue = dscEngine.getUsdValue(weth, totalWethDeposited) +
            dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("Total DSC Supply:", totalSupply);
        console.log("Total Collateral Value in USD:", totalCollateralValue);
        console.log("Times Mint is called:", handler.timesMintIsCalled());


        assert(totalSupply <= totalCollateralValue);    
    }

    function invariant_GettersNeverRevert() public view {
        // Put all getters here
        dscEngine.getCollateralTokens();
        dscEngine.getAccountCollateralValue(address(1));
        dscEngine.getUsdValue(weth, 1e18);
        dscEngine.getMaxMintableDsc(address(1));
    }

}