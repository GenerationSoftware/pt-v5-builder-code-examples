// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import {
    PrizeCompoundingSwapperHookAndClaimer,
    PrizeCompoundingSwapperHook,
    PrizeVault,
    IUniV3Oracle,
    ISwapperFactory,
    ISwapper,
    IUniswapV3Router,
    IERC20,
    QuoteParams,
    QuotePair
} from "src/prize-hooks/examples/prize-compounding-swapper/PrizeCompoundingSwapperHookAndClaimer.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { IPrizeHooks, PrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";

contract PrizeCompoundingSwapperHookAndClaimerTest is Test, IPrizeHooks {

    uint256 fork;
    uint256 forkBlock = 19393711;
    uint256 forkTimestamp = 1725576769;

    PrizeCompoundingSwapperHookAndClaimer public hookAndClaimer;

    PrizeVault public przWETH = PrizeVault(address(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43));
    PrizeVault public przPOOL = PrizeVault(address(0x6B5a5c55E9dD4bb502Ce25bBfbaA49b69cf7E4dd));
    PrizeVault public przUSDC = PrizeVault(address(0x7f5C2b379b88499aC2B997Db583f8079503f25b9));

    address public WETH = address(0x4200000000000000000000000000000000000006);
    address public POOL = address(0xd652C5425aea2Afd5fb142e120FeCf79e18fafc3);
    address public wethWhale = address(0xcDAC0d6c6C59727a65F871236188350531885C43);
    IUniV3Oracle public baseOracle = IUniV3Oracle(address(0x6B99b2E868B6E3B8b259E296c4c6aBffbB1AaB94));
    ISwapperFactory public swapperFactory = ISwapperFactory(address(0xa244bbe019cf1BA177EE5A532250be2663Fb55cA));
    IUniswapV3Router public uniV3Router = IUniswapV3Router(address(0x2626664c2603336E57B271c5C0b26F421741e481));
    uint32 public defaultScaleFactor = uint32(99e4); // 99% (1% discount to swappers)

    address public alice;

    uint8 public winTier = 5;
    address[] public winners = [
        address(0x08DE07fE4B53F315A1C93cA8396c18985432d41E),
        address(0xd682fb159a2cBC47DE97A046D76391dDae104988)
    ];
    uint32[] public winner0PrizeIndices = [417, 766];
    uint32[] public winner1PrizeIndices = [258];
    uint32[][] public prizeIndices = [
        winner0PrizeIndices,
        winner1PrizeIndices
    ];

    function setUp() public {
        fork = vm.createFork('base', forkBlock);
        vm.selectFork(fork);
        vm.warp(forkTimestamp);
        alice = makeAddr("Alice");
        hookAndClaimer = new PrizeCompoundingSwapperHookAndClaimer(
            uniV3Router,
            baseOracle,
            swapperFactory,
            przUSDC,
            defaultScaleFactor
        );

        vm.startPrank(przUSDC.owner());
        przUSDC.setClaimer(address(hookAndClaimer));
        vm.stopPrank();
    }

    function testQuoteWethToPrzWeth() external {
        QuoteParams[] memory quoteParams = new QuoteParams[](1);
        quoteParams[0] = QuoteParams({
            quotePair: QuotePair({
                base: WETH,
                quote: address(przWETH)
            }),
            baseAmount: 1e18,
            data: ""
        });
        uint256[] memory amounts = hookAndClaimer.getQuoteAmounts(quoteParams);
        assertEq(amounts[0], 1e18);
    }

    function testQuotePoolToPrzPool() external {
        QuoteParams[] memory quoteParams = new QuoteParams[](1);
        quoteParams[0] = QuoteParams({
            quotePair: QuotePair({
                base: POOL,
                quote: address(przPOOL)
            }),
            baseAmount: 1e18,
            data: ""
        });
        uint256[] memory amounts = hookAndClaimer.getQuoteAmounts(quoteParams);
        assertEq(amounts[0], 1e18);
    }

    function testQuoteWethToPrzUsdc() external {
        QuoteParams[] memory quoteParams = new QuoteParams[](1);
        quoteParams[0] = QuoteParams({
            quotePair: QuotePair({
                base: WETH,
                quote: address(przUSDC)
            }),
            baseAmount: 1e18,
            data: ""
        });
        uint256[] memory amounts = hookAndClaimer.getQuoteAmounts(quoteParams);
        assertApproxEqAbs(amounts[0], 2366e6, 10e6);
    }

    function testQuoteWethToUsdc() external {
        QuoteParams[] memory quoteParams = new QuoteParams[](1);
        quoteParams[0] = QuoteParams({
            quotePair: QuotePair({
                base: WETH,
                quote: przUSDC.asset()
            }),
            baseAmount: 1e18,
            data: ""
        });
        uint256[] memory amounts = hookAndClaimer.getQuoteAmounts(quoteParams);
        assertApproxEqAbs(amounts[0], 2366e6, 10e6);
    }

    function testSetSwapperDoesNothingIfSet() external {
        vm.startPrank(alice);
        assertEq(hookAndClaimer.swappers(alice), address(0));

        vm.expectEmit(true, false, true, false);
        emit PrizeCompoundingSwapperHook.SetSwapper(alice, address(0), address(0));
        ISwapper swapper = hookAndClaimer.setSwapper();
        assertEq(hookAndClaimer.swappers(alice), address(swapper));
        assertNotEq(address(swapper), address(0));

        ISwapper swapperSame = hookAndClaimer.setSwapper();
        assertEq(hookAndClaimer.swappers(alice), address(swapper));
        assertEq(address(swapperSame), address(swapper));
        vm.stopPrank();
    }

    function testRemoveAndRecoverSwapper() external {
        vm.startPrank(alice);
        assertEq(hookAndClaimer.swappers(alice), address(0));
        ISwapper swapper = hookAndClaimer.setSwapper();
        assertEq(hookAndClaimer.swappers(alice), address(swapper));
        assertEq(swapper.owner(), address(hookAndClaimer));

        vm.expectEmit();
        emit PrizeCompoundingSwapperHook.SetSwapper(alice, address(0), address(swapper));
        address oldSwapper = hookAndClaimer.removeAndRecoverSwapper();
        assertEq(oldSwapper, address(swapper));
        assertEq(swapper.owner(), alice);
        assertEq(hookAndClaimer.swappers(alice), address(0));
        vm.stopPrank();
    }

    function testSetPrizeSizeVote() external {
        vm.startPrank(alice);
        assertEq(hookAndClaimer.prizeSizeVotes(alice), 0);
        vm.expectEmit();
        emit PrizeCompoundingSwapperHook.SetPrizeSizeVote(alice, 1e6);
        hookAndClaimer.setPrizeSizeVote(1e6);
        assertEq(hookAndClaimer.prizeSizeVotes(alice), 1e6);
        vm.stopPrank();
    }

    function testSetPrizeSizeVote_setBackToZero() external {
        vm.startPrank(alice);
        assertEq(hookAndClaimer.prizeSizeVotes(alice), 0);
        hookAndClaimer.setPrizeSizeVote(1e6);
        assertEq(hookAndClaimer.prizeSizeVotes(alice), 1e6);

        vm.expectEmit();
        emit PrizeCompoundingSwapperHook.SetPrizeSizeVote(alice, 0);
        hookAndClaimer.setPrizeSizeVote(0);
        assertEq(hookAndClaimer.prizeSizeVotes(alice), 0);
        vm.stopPrank();
    }

    function testPrizeSizeVoting() external {
        vm.startPrank(alice);

        uint8 numTiers = hookAndClaimer.prizePool().numberOfTiers();
        uint8 canaryLow = numTiers - 2;
        uint8 canaryHigh = numTiers - 1;

        // no vote set, no revert
        hookAndClaimer.beforeClaimPrize(alice, canaryLow, uint32(0), uint96(0), address(0));
        hookAndClaimer.beforeClaimPrize(alice, canaryHigh, uint32(0), uint96(0), address(0));

        // vote really small prize ($0.05), no revert either
        hookAndClaimer.setPrizeSizeVote(0.05e6);
        hookAndClaimer.beforeClaimPrize(alice, canaryLow, uint32(0), uint96(0), address(0));
        hookAndClaimer.beforeClaimPrize(alice, canaryHigh, uint32(0), uint96(0), address(0));

        // vote near current prize size ($0.50), revert high, but not low
        hookAndClaimer.setPrizeSizeVote(0.5e6);
        hookAndClaimer.beforeClaimPrize(alice, canaryLow, uint32(0), uint96(0), address(0));
        try hookAndClaimer.beforeClaimPrize(alice, canaryHigh, uint32(0), uint96(0), address(0)) returns (address, bytes memory) {
            // nothing
            revert("should have reverted");
        } catch (bytes memory reason) {
            bytes4 errorSelector = abi.decode(reason, (bytes4));
            assertEq(errorSelector, PrizeCompoundingSwapperHook.VoteToStayAtCurrentPrizeTiers.selector);
            (bool success, bytes memory data) = address(this).staticcall(reason);
            (uint8 currentTiers, uint256 dailyPrizeSize, uint256 minDesiredDailyPrizeSize) = abi.decode(data, (uint8,uint256,uint256));
            assertEq(currentTiers, numTiers);
            assertEq(minDesiredDailyPrizeSize, 0.5e6);
            assertGt(dailyPrizeSize, minDesiredDailyPrizeSize);
        }

        // vote higher than current prize size ($20.00), revert both
        hookAndClaimer.setPrizeSizeVote(20e6);
        try hookAndClaimer.beforeClaimPrize(alice, canaryLow, uint32(0), uint96(0), address(0)) returns (address, bytes memory) {
            // nothing
            revert("should have reverted");
        } catch (bytes memory reason) {
            bytes4 errorSelector = abi.decode(reason, (bytes4));
            assertEq(errorSelector, PrizeCompoundingSwapperHook.VoteToLowerPrizeTiers.selector);
            (bool success, bytes memory data) = address(this).staticcall(reason);
            (uint8 currentTiers, uint256 dailyPrizeSize, uint256 minDesiredDailyPrizeSize) = abi.decode(data, (uint8,uint256,uint256));
            assertEq(currentTiers, numTiers);
            assertEq(minDesiredDailyPrizeSize, 20e6);
            assertLt(dailyPrizeSize, minDesiredDailyPrizeSize);
        }
        try hookAndClaimer.beforeClaimPrize(alice, canaryHigh, uint32(0), uint96(0), address(0)) returns (address, bytes memory) {
            // nothing
            revert("should have reverted");
        } catch (bytes memory reason) {
            bytes4 errorSelector = abi.decode(reason, (bytes4));
            assertEq(errorSelector, PrizeCompoundingSwapperHook.VoteToLowerPrizeTiers.selector);
            (bool success, bytes memory data) = address(this).staticcall(reason);
            (uint8 currentTiers, uint256 dailyPrizeSize, uint256 minDesiredDailyPrizeSize) = abi.decode(data, (uint8,uint256,uint256));
            assertEq(currentTiers, numTiers);
            assertEq(minDesiredDailyPrizeSize, 20e6);
            assertLt(dailyPrizeSize, minDesiredDailyPrizeSize);
        }
        
        vm.stopPrank();
    }

    function testPrizeSizeVoting_OracleRevertFallback() external {
        vm.startPrank(alice);

        uint8 numTiers = hookAndClaimer.prizePool().numberOfTiers();
        uint8 canaryLow = numTiers - 2;
        uint8 canaryHigh = numTiers - 1;

        (bool _success, bytes memory _tempData) = address(baseOracle).staticcall(abi.encodeWithSignature("sequencerFeed()"));
        assertEq(_success, true);
        address _sequencer = abi.decode(_tempData, (address));
        vm.mockCallRevert(address(_sequencer), abi.encodeWithSignature("latestRoundData()"), "revert");

        hookAndClaimer.setPrizeSizeVote(1e6);
        (address recipient, bytes memory data) = hookAndClaimer.beforeClaimPrize(alice, canaryLow, uint32(0), uint96(0), address(0));
        assertEq(recipient, alice);
        assertEq(keccak256(data), keccak256("vote-abstained"));

        vm.stopPrank();
    }

    function testClaimPrizesWithCompounding_swappersNotSetForClaims() external {
        vm.expectEmit();
        emit PrizeCompoundingSwapperHookAndClaimer.SwapperNotSetForAccount(winners[0]);
        vm.expectEmit();
        emit PrizeCompoundingSwapperHookAndClaimer.SwapperNotSetForAccount(winners[1]);
        vm.expectRevert(abi.encodeWithSelector(PrizeCompoundingSwapperHookAndClaimer.MinRewardNotMet.selector, 0, 1));
        hookAndClaimer.claimPrizes(winTier, winners, prizeIndices, alice, 1);
    }

    function testClaimPrizesWithCompounding() external {
        vm.startPrank(winners[0]);
        hookAndClaimer.setSwapper();
        przUSDC.setHooks(PrizeHooks(true, false, hookAndClaimer));
        vm.stopPrank();
        vm.startPrank(winners[1]);
        hookAndClaimer.setSwapper();
        przUSDC.setHooks(PrizeHooks(true, false, hookAndClaimer));
        vm.stopPrank();

        uint256 winner0PrzUsdcBalanceBefore = przUSDC.balanceOf(winners[0]);
        uint256 winner1PrzUsdcBalanceBefore = przUSDC.balanceOf(winners[1]);

        uint256 totalReward = hookAndClaimer.claimPrizes(winTier, winners, prizeIndices, alice, 1);
        assertGt(totalReward, 7.5e12);
        assertEq(IERC20(WETH).balanceOf(alice), totalReward);

        assertGt(przUSDC.balanceOf(winners[0]), winner0PrzUsdcBalanceBefore + 1e6); // more than $1 in prize value added
        assertGt(przUSDC.balanceOf(winners[1]), winner1PrzUsdcBalanceBefore + 0.5e6); // more than $0.50 in prize value added
    }

    function testClaimPrizesFallbackPeriod() external {
        // only set one winner's hooks to test both work in fallback period
        vm.startPrank(winners[0]);
        hookAndClaimer.setSwapper();
        przUSDC.setHooks(PrizeHooks(true, false, hookAndClaimer));
        vm.stopPrank();

        uint256 drawClosed = hookAndClaimer.prizePool().drawClosesAt(hookAndClaimer.prizePool().getLastAwardedDrawId());
        uint256 drawPeriod = hookAndClaimer.prizePool().drawPeriodSeconds();
        vm.warp(drawClosed + (drawPeriod * 3) / 4 + 1); // in fallback period

        uint256 snap = vm.snapshot();

        uint256 totalReward = hookAndClaimer.claimPrizes(winTier, winners, prizeIndices, alice, 1);
        assertGt(totalReward, 7.5e12); // should still be around 1% in start of fallback period
        assertEq(IERC20(WETH).balanceOf(alice), totalReward);

        vm.revertTo(snap);
        vm.warp(drawClosed + drawPeriod - 1); // end of fallback period

        totalReward = hookAndClaimer.claimPrizes(winTier, winners, prizeIndices, alice, 1);
        assertGt(totalReward, 7.5e13); // should be around 10% at end of fallback period
        assertEq(IERC20(WETH).balanceOf(alice), totalReward);
    }

    function testClaimPrizes_noReentrancy() external {
        // set winner to reenter claimPrizes with custom hook
        vm.startPrank(winners[0]);
        przUSDC.setHooks(PrizeHooks(true, false, this));
        vm.stopPrank();

        // other winner will be normal
        vm.startPrank(winners[1]);
        hookAndClaimer.setSwapper();
        przUSDC.setHooks(PrizeHooks(true, false, hookAndClaimer));
        vm.stopPrank();

        vm.expectEmit();
        emit PrizeCompoundingSwapperHookAndClaimer.ClaimError(przUSDC, winTier, winners[0], 417, "");
        hookAndClaimer.claimPrizes(winTier, winners, prizeIndices, alice, 1);
    }

    // helpers for decoding error data
    function VoteToStayAtCurrentPrizeTiers(uint8 currentTiers, uint256 dailyPrizeSize, uint256 minDesiredDailyPrizeSize) external view returns (uint8,uint256,uint256) {
        return (currentTiers, dailyPrizeSize, minDesiredDailyPrizeSize);
    }
    function VoteToLowerPrizeTiers(uint8 currentTiers, uint256 dailyPrizeSize, uint256 minDesiredDailyPrizeSize) external view returns (uint8,uint256,uint256) {
        return (currentTiers, dailyPrizeSize, minDesiredDailyPrizeSize);
    }

    /// @inheritdoc IPrizeHooks
    /// @dev used to test reentrancy to the `claimPrizes` function
    function beforeClaimPrize(address, uint8, uint32, uint96, address) external returns (address prizeRecipient, bytes memory data) {
        hookAndClaimer.claimPrizes(winTier, winners, prizeIndices, address(this), 1);
    }

    /// @inheritdoc IPrizeHooks
    function afterClaimPrize(address, uint8, uint32, uint256, address, bytes memory) external { }

}
