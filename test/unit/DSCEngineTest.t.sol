// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from 'forge-std/Test.sol';
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
    address wbtc;
    address btcUsdPriceFeed;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc,dscEngine,config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,wbtc,) = config.getActiveNetworkConfig();

        ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);
        console.log("Initial DSC total supply:", dsc.totalSupply());
        console.log("Deployer DSC balance:", dsc.balanceOf(msg.sender));    
    }

///////// CONSTRUCTOR TESTS ////////// 
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsAreNotTheSame.selector);
        new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
    }
        
///////// PRICE TESTS ////////// 

    function testGetUsdValue() public view{
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth,ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether; // Because usd amount has 18 decimal places in the funciton tested
        uint256 expectedEth = 0.05 ether;
        uint256 actualEth = dscEngine.getTokenAmountFromUsd(weth,usdAmount);
        assertEq(expectedEth, actualEth);
    }

///////// DEPOSIT COLLATERAL TESTS //////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);
        
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth,0);
        
        vm.stopPrank();   
    }

    function testRevertIfTokenNotAllowed() public {
        ERC20Mock notAllowedToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(notAllowedToken),AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier collateralDeposited() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth,AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public collateralDeposited {
        
        (uint256 totalDscMinted,uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedDscMinted = 0;
        uint256 expectedDeposit = dscEngine.getTokenAmountFromUsd(weth,collateralValueInUsd);

        console.log("Total DSC Minted:",totalDscMinted);
        
        assertEq(totalDscMinted,expectedDscMinted);
        assertEq(expectedDeposit,AMOUNT_COLLATERAL);
    }

///////// HEALTH FACTOR TESTS //////////

    function testHealthFactorIsMaxIfNoDscMinted() public {
        // User has deposited collateral but hasn't minted any DSC yet
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 healthFactor = dscEngine.getHealthFactor(USER);

        // When no DSC is minted, health factor should be type(uint256).max
        assertEq(healthFactor, type(uint256).max);
    }

    function testHealthFactorIsOneAfterMintingExactLimit() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        // Calculate max DSC to mint based on collateral and liquidation threshold
        uint256 collateralValueInUsd = dscEngine.getAccountCollateralValue(USER);
        uint256 maxDscToMint = (collateralValueInUsd * 50) / 100; // 50% threshold
        console.log("Collateral Value in USD:", collateralValueInUsd);
        console.log("Max DSC to mint:", maxDscToMint);
        dscEngine.mintDsc(maxDscToMint);
        vm.stopPrank();

        uint256 healthFactor = dscEngine.getHealthFactor(USER);

        // Should be around MINIMUM_HEALTH_FACTOR (1e18)
        assertEq(healthFactor, 1e18);
    }

    function testHealthFactorIsOneWithHardcodedValues() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
    dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

    // Hardcoded collateral value and DSC to mint
    // Collateral: 10 ETH, Price: $2000 per ETH → 10 * 2000 = 20000 USD
    // Liquidation threshold: 50% → max DSC to mint = 20000 * 50 / 100 = 10000 DSC
    uint256 hardcodedDscToMint = 10000e18; // 10000 DSC with 18 decimals

    dscEngine.mintDsc(hardcodedDscToMint);
    vm.stopPrank();

    uint256 healthFactor = dscEngine.getHealthFactor(USER);

    // Should equal MINIMUM_HEALTH_FACTOR (1e18)
    assertEq(healthFactor, 1e18);
    }

    

}