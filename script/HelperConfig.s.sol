// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from 'forge-std/Script.sol';
import {MockV3Aggregator} from '../test/unit/mocks/MockV3Aggregator.sol';
import {ERC20Mock} from '@openzeppelin/contracts/mocks/token/ERC20Mock.sol';

contract HelperConfig is Script {

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey; // private key
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 5000e8;
    uint256 public constant DEFAULT_ANVIL_KEY = 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356;

    NetworkConfig public activeNetworkConfig;

    constructor () {
        if(block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed:0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed:0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth:0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wbtc:0x16EFdA168bDe70E05CA6D349A690749d622F95e0,
            deployerKey:vm.envUint("PRIVATE_KEY")
            });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if(activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS,BTC_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock();
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
        wethUsdPriceFeed: address(ethUsdPriceFeed),
        wbtcUsdPriceFeed: address(btcUsdPriceFeed),
        weth: address(wethMock),
        wbtc: address(wbtcMock),
        deployerKey:  DEFAULT_ANVIL_KEY
        });

    }

    function getActiveNetworkConfig() public view returns (address, address, address, address, uint256) {
        return (activeNetworkConfig.wethUsdPriceFeed,
        activeNetworkConfig.wbtcUsdPriceFeed,
        activeNetworkConfig.weth,
        activeNetworkConfig.wbtc,
        activeNetworkConfig.deployerKey);
    }

}