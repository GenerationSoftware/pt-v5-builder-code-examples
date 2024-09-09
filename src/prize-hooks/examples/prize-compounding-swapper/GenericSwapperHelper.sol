// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ISwapperFlashCallback } from "./interfaces/ISwapperFlashCallback.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";
import { QuoteParams, QuotePair } from "./interfaces/IOracle.sol";
import { IERC20 } from "openzeppelin-v5/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-v5/token/ERC20/utils/SafeERC20.sol";

/// @notice Structured flash info
/// @param profitRecipient The recipient of any profit (`tokenToBeneficiary` OR `tokenToSwap`)
/// @param tokenToSwap The token to pull from the swapper that will be used to swap
/// @param amountToSwap The amount of `tokenToSwap` to pull from the swapper
/// @param minTokenToSwapProfit The min amount of `tokenToSwap` profit that is expected to be sent to the
/// `profitRecipient` after the flash swap
/// @param minTokenToBeneficiaryProfit The min amount of `tokenToBeneficiary` profit that is expected to
/// be sent to the `profitRecipient` after the flash swap
/// @param approveTo The 
struct FlashInfo {
    address profitRecipient;
    address tokenToSwap;
    uint128 amountToSwap;
    uint128 minTokenToSwapProfit;
    uint256 minTokenToBeneficiaryProfit;
    address approveTo;
    address callTarget;
    bytes callData;
}

/// @title Generic Swapper Helper
/// @notice Provides a generic interface for performing single ERC20 flash swaps with a 0xSplits Swapper.
/// @author G9 Software Inc.
contract GenericSwapperHelper is ISwapperFlashCallback {
    using SafeERC20 for IERC20;

    /// @notice Thrown when the min token profit is not met.
    /// @param token The token expected as profit
    /// @param actualProfit The actual profit that would have been received
    /// @param minProfit The min profit set on the flash swap
    error MinProfitNotMet(address token, uint256 actualProfit, uint256 minProfit);

    /// @notice Performs a flash swap on the swapper with the given flash info.
    /// @dev If `flashInfo.profitRecipient` is left as the zero address, it will be set to the caller
    /// @dev If `flashInfo.amountToSwap` is left as zero, it will be set to the swapper's balance
    /// @dev If `flashInfo.approveTo` is left as the zero address, it will be set to the `flashInfo.callTarget` address
    /// @param swapper The swapper to pull tokens from
    /// @param flashInfo The flash info for the swap
    function flashSwap(ISwapper swapper, FlashInfo memory flashInfo) external {
        if (flashInfo.profitRecipient == address(0)) {
            flashInfo.profitRecipient = msg.sender;
        }
        if (flashInfo.amountToSwap == 0) {
            flashInfo.amountToSwap = uint128(IERC20(flashInfo.tokenToSwap).balanceOf(address(swapper)));
        }
        if (flashInfo.approveTo == address(0)) {
            flashInfo.approveTo = flashInfo.callTarget;
        }
        QuoteParams[] memory quoteParams = new QuoteParams[](1);
        quoteParams[0] = QuoteParams({
            quotePair: QuotePair({
                base: flashInfo.tokenToSwap,
                quote: swapper.tokenToBeneficiary()
            }),
            baseAmount: flashInfo.amountToSwap,
            data: ""
        });
        swapper.flash(quoteParams, abi.encode(flashInfo));
    }

    /// @inheritdoc ISwapperFlashCallback
    /// @dev Sends profit from both the `tokenToBeneficiary` and `tokenToSwap` to the `profitRecipient`.
    function swapperFlashCallback(address tokenToBeneficiary, uint256 amountToBeneficiary, bytes calldata data) external {
        FlashInfo memory flashInfo = abi.decode(data, (FlashInfo));
        IERC20(flashInfo.tokenToSwap).forceApprove(flashInfo.approveTo, flashInfo.amountToSwap);
        (bool success, bytes memory returnData) = flashInfo.callTarget.call(flashInfo.callData);
        if (!success) {
            assembly {
                revert(add(32, returnData), mload(returnData))
            }
        }

        uint256 tokenToBeneficiaryBalance = IERC20(tokenToBeneficiary).balanceOf(address(this));
        IERC20(tokenToBeneficiary).forceApprove(msg.sender, amountToBeneficiary);
        if (tokenToBeneficiaryBalance > amountToBeneficiary) {
            uint256 profit = tokenToBeneficiaryBalance - amountToBeneficiary;
            if (profit < flashInfo.minTokenToBeneficiaryProfit) {
                revert MinProfitNotMet(tokenToBeneficiary, profit, flashInfo.minTokenToBeneficiaryProfit);
            }
            IERC20(tokenToBeneficiary).safeTransfer(flashInfo.profitRecipient, profit);
        }

        uint256 tokenToSwapBalance = IERC20(flashInfo.tokenToSwap).balanceOf(address(this));
        if (tokenToSwapBalance > 0) {
            if (tokenToSwapBalance < flashInfo.minTokenToSwapProfit) {
                revert MinProfitNotMet(flashInfo.tokenToSwap, tokenToSwapBalance, flashInfo.minTokenToSwapProfit);
            }
            IERC20(flashInfo.tokenToSwap).safeTransfer(flashInfo.profitRecipient, tokenToSwapBalance);
        }
    }

}