// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { IERC4626 } from "openzeppelin-v5/interfaces/IERC4626.sol";
import { IOracle, QuoteParams } from "./interfaces/IOracle.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";
import { ISwapperFactory, CreateSwapperParams, OracleParams, CreateOracleParams, SetPairScaledOfferFactorParams } from "./interfaces/ISwapperFactory.sol";

/// @notice Emitted when an account sets a new swapper.
/// @param account The account setting the swapper
/// @param newTokenOut The token that the new swapper is set to swap to
/// @param newSwapper The new swapper address
/// @param previousSwapper The previous swapper address
event SetSwapper(address indexed account, address indexed newTokenOut, ISwapper indexed newSwapper, address previousSwapper);

/// @title PoolTogether V5 - Prize Compounding Swapper Hook
/// @notice Uses the 0xSplits Swapper contract factory to let users create their own swappers
/// that will receive any prizes won through this hook. External actors can then swap their
/// winnings back to the token or prize token they specify (assuming the base oracle has a 
/// price for the token or underlying asset).
/// @author G9 Software Inc.
contract PrizeCompoundingSwapperHook is IPrizeHooks, IOracle {

    /// @notice The underlying oracle to pull asset prices from
    IOracle public immutable baseOracle;

    /// @notice The swapper factory to create new swappers from
    ISwapperFactory public immutable swapperFactory;

    /// @notice The default scaled offer factor that is used for swaps (1e6 is 100%, over is premium to oracle, under is discount to oracle)
    uint32 public immutable defaultScaledOfferFactor;

    /// @notice Mapping of accounts to swappers.
    mapping(address account => address swapper) public swappers;
    
    /// @notice Constructor
    constructor(IOracle baseOracle_, ISwapperFactory swapperFactory_, uint32 defaultScaledOfferFactor_) {
        baseOracle = baseOracle_;
        swapperFactory = swapperFactory_;
        defaultScaledOfferFactor = defaultScaledOfferFactor_;
    }

    /// @notice Creates a new swapper for the caller and sets prizes to be redirected to their swapper.
    /// @dev If the caller had a previous swapper set, it will transfer the ownership of that swapper to
    /// the caller so they can recover any funds that are stuck.
    /// @param _tokenOut The token to swap prizes to and send to the caller
    /// @return The new swapper that is set for the caller
    function setSwapper(address _tokenOut) external returns (ISwapper) {
        address _previousSwapper = swappers[msg.sender];
        if (_previousSwapper != address(0)) {
            ISwapper(_previousSwapper).transferOwnership(msg.sender);
        }
        ISwapper _swapper = swapperFactory.createSwapper(
            CreateSwapperParams({
                owner: address(this),
                paused: false,
                beneficiary: msg.sender,
                tokenToBeneficiary: _tokenOut,
                oracleParams: OracleParams({
                    oracle: this,
                    createOracleParams: CreateOracleParams(address(0), "")
                }),
                defaultScaledOfferFactor: defaultScaledOfferFactor,
                pairScaledOfferFactors: new SetPairScaledOfferFactorParams[](0)
            })
        );
        swappers[msg.sender] = address(_swapper);
        emit SetSwapper(msg.sender, _tokenOut, _swapper, _previousSwapper);
        return _swapper;
    }

    /// @inheritdoc IOracle
    /// @dev Remaps the quote token addresses to the underlying 4626 `asset` if supported before passing
    /// the quote call to the base oracle.
    /// @dev THIS ENFORCES THAT THE 4626 TOKEN HAS A ONE-TO-ONE CONVERSION WITH THE UNDERLYING ASSET.
    /// @dev Fails if the oracle has a `sequencerFeed` with an invalid round. This enables backwards compatibility 
    /// with old 0xSplits oracles.
    function getQuoteAmounts(QuoteParams[] memory quoteParams) public view returns (uint256[] memory) {
        for (uint256 i; i < quoteParams.length; i++) {
            try IERC4626(quoteParams[i].quotePair.quote).asset() returns (address _asset) {
                assert(IERC4626(quoteParams[i].quotePair.quote).convertToAssets(1) == 1);
                quoteParams[i].quotePair.quote = _asset;
            } catch {
                // nothing
            }
        }
        (bool _success, bytes memory _tempData) = address(baseOracle).staticcall(abi.encodeWithSignature("sequencerFeed()"));
        if (_success) {
            address _sequencer = abi.decode(_tempData, (address));
            (_success, _tempData) = _sequencer.staticcall(abi.encodeWithSignature("latestRoundData()"));
            assert(_success);
            (,,uint256 startedAt,,) = abi.decode(_tempData, (uint80,int256,uint256,uint256,uint80));
            assert(startedAt != 0); // invalid round
        }
        return baseOracle.getQuoteAmounts(quoteParams);
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Maps the winner address to their defined swapper contract and redirects the prize there.
    /// @dev If no swapper exists for the winner, the recipient will be set to the winner address.
    function beforeClaimPrize(address winner, uint8, uint32, uint96, address) external view returns (address prizeRecipient, bytes memory data) {
        address _swapper = swappers[winner];
        if (_swapper == address(0)) {
            prizeRecipient = address(winner);
        } else {
            prizeRecipient = _swapper;
        }
    }

    /// @inheritdoc IPrizeHooks
    /// @dev Does nothing, but is still required by the interface.
    function afterClaimPrize(address, uint8, uint32, uint256, address, bytes memory) external { }
}