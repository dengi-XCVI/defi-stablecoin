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
 * @title DSCEngine
 * @author Dennis Gianassi
 * The system is designed as minimal as possible, and have the tokens maintain 1:1 peg with USD.
 * This stablecoin has the properties:
 * - Exogenous collateral
 * - Dollar pegged
 * - Algorithmically stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should be overcollateralized. At no point should the USD value of the collateral be <= $ backed value of all of the DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is loosely based on the MakerDAO DSS (DAI STablecoin System).
 */
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {AggregatorV3Interface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol'; 

contract DSCEngine is ReentrancyGuard {
    // Errors

    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsAreNotTheSame();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    // State variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // Chainlink price feeds have commonly 8 decimals
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable I_DSC;

    // Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    // Modifiers

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    // Functions

    constructor(address[] memory _tokenAddresses, address[] memory _priceFeedAddresses, address _dscAddress) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsAreNotTheSame();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        I_DSC = DecentralizedStableCoin(_dscAddress);
    }

    // External functions

    /**
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount of collateral to deposit
     * @param _dscToMint The amount of DSC to mint
     * @notice This function deposits collateral and mints DSC in a single transaction 
     * */ 
    function depositCollateralAndMintDsc(address _tokenCollateralAddress, uint256 _amountCollateral, uint256 _dscToMint) external {
        depositCollateral(_tokenCollateralAddress, _amountCollateral);
        mintDsc(_dscToMint);
    }

    /**
     * @notice Follows CEI pattern: Checks-Effects-Interactions
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * 
     * @param _tokenCollateralAddress  The address of the token to redeem as collateral
     * @param _amountCollateral  The amount of the collateral to redeem
     * @param _amountDscToBurn  AMount of DSC to burn
     * @notice This function redeems collateral and burns DSC in a single transaction
     */
    function redeemCollateralForDsc(address _tokenCollateralAddress, uint256 _amountCollateral, uint256 _amountDscToBurn) external {
        burnDsc(_amountDscToBurn);
        redeemCollateral(_tokenCollateralAddress, _amountCollateral);
        // redeem collateral already checks health factor
    }

    function redeemCollateral(address _tokenCollateral, uint256 _amountCollateral) public moreThanZero(_amountCollateral) nonReentrant{
        _redeemCollateral(msg.sender, msg.sender, _tokenCollateral, _amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI pattern: Checks-Effects-Interactions
     * @param _amountDscToMint The amount of DSC to mint
     * @notice Must have more collateral than the minimum threshold
     */
    function mintDsc(uint256 _amountDscToMint) moreThanZero(_amountDscToMint) nonReentrant public {
        s_dscMinted[msg.sender] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = I_DSC.mint(msg.sender, _amountDscToMint);
        if(!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 _amount) public moreThanZero(_amount) nonReentrant  {
        _burnDsc(msg.sender,msg.sender,_amount);
        _revertIfHealthFactorIsBroken(msg.sender); // Probably not needed, maybe if user burns too much
    }

    /**
     * @param _tokenCollateral The address of the collateral token to liquidate
     * @param _user The user to who has broken the health factor and needs to be liquidated
     * @param _debtToCover The amount of DSC to burn (repay) for the user
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus if you are the liquidator
     * @notice This function working asssumes the protocol will be 200% overcollateralized in this scenario
     * @notice Overcollateralization allows the protocol to incentivize liquidators
     * For example, if price of collateral plummets before someone is able to liquidate
     * Follows CEI: Checks-Effects-Interactions
     */
    function liquidate(address _tokenCollateral, address _user, uint256 _debtToCover) external moreThanZero(_debtToCover) nonReentrant {
        uint256 startingUserlHealthFactor = _healthFactor(_user);
        if (startingUserlHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCoverd = getTokenAmountFromUsd(_tokenCollateral, _debtToCover);

        // Liquidator also gets a 10% bonus, for 100$ of debt covered, liquidator gets 110$
        uint256 bonusCollateral = (tokenAmountFromDebtCoverd * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCoverd + bonusCollateral;
        _redeemCollateral(_user, msg.sender, _tokenCollateral, totalCollateralToRedeem);
        _burnDsc(_user, msg.sender, _debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(_user);
        if (endingUserHealthFactor <= startingUserlHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    // Private & Internal functions

    /**
     * 
     * @dev Low-level internal functions, do not call unless health factor is checked in the function calling them 
     */
    function _burnDsc(address _onBehalfOf, address _dscFrom,uint256 _amount) private {
        s_dscMinted[_onBehalfOf] -= _amount;
        bool success = I_DSC.transferFrom(_dscFrom, address(this), _amount);

        // Following error not really needed since DSC's transferFrom will revert if it fails
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        I_DSC.burn(_amount);
    }

    function _redeemCollateral(address _from, address _to, address _tokenCollateral, uint256 _amount) private {
        s_collateralDeposited[_from][_tokenCollateral] -= _amount;
        emit CollateralRedeemed(_from, _to, _tokenCollateral, _amount);
        bool success = IERC20(_tokenCollateral).transfer(_to, _amount);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _getAccountInformation(address _user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_dscMinted[_user];
        collateralValueInUsd = getAccountCollateralValue(_user);
        return (totalDscMinted, collateralValueInUsd);
    }

    /**
     * Returns how close a user is to liquidation
     * If health factor is below 1, user can be liquidated
     */
    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(_user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if(userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    // Public & External View functions

    function getTokenAmountFromUsd(address _tokenCollateral, uint256 _usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenCollateral]);
        (,int256  price,,,) = priceFeed.latestRoundData();

        return (_usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address _user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd = 0;
        for(uint i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 tokenAmount = s_collateralDeposited[_user][token];
            totalCollateralValueInUsd += getUsdValue(token, tokenAmount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
