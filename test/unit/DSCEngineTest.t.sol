// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from 'forge-std/Test.sol';
import {DeployDSC} from '../../script/DeployDSC.s.sol';
import {DecentralizedStableCoin} from '../../src/DecentralizedStableCoin.sol';
import {DSCEngine} from '../../src/DSCEngine.sol';
import {HelperConfig} from '../../script/HelperConfig.s.sol';
import {ERC20Mock} from '@openzeppelin/contracts/mocks/token/ERC20Mock.sol';


contract DscEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc,dscEngine,config) = deployer.run();
        (ethUsdPriceFeed,,weth,,) = config.getActiveNetworkConfig();

        ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);
    }

///////// PRICE TESTS ////////// 

    function testGetUsdValue() public view{
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth,ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

///////// DEPOSIT COLLATERAL TESTS //////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);
        
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth,0);
        
        vm.stopPrank();
        
    }

}