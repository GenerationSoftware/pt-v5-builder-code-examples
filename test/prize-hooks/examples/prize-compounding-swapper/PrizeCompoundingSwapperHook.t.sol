// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { PrizeCompoundingSwapperHook, IERC4626, IOracle, ISwapperFactory, ISwapper } from "src/prize-hooks/examples/prize-compounding-swapper/PrizeCompoundingSwapperHook.sol";
import { GenericSwapperHelper, FlashInfo, IERC20, QuoteParams, QuotePair } from "src/prize-hooks/examples/prize-compounding-swapper/GenericSwapperHelper.sol";
import { PrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";

contract PrizeCompoundingSwapperHookTest is Test {

    uint256 fork;
    uint256 forkBlock = 19424769;
    uint256 forkTimestamp = 1725638885;

    PrizeCompoundingSwapperHook public prizeCompoundingSwapperHook;
    GenericSwapperHelper public swapperHelper;

    IERC4626 public przWETH = IERC4626(address(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43));
    IERC4626 public przPOOL = IERC4626(address(0x6B5a5c55E9dD4bb502Ce25bBfbaA49b69cf7E4dd));
    IERC4626 public przUSDC = IERC4626(address(0x7f5C2b379b88499aC2B997Db583f8079503f25b9));

    address public WETH = address(0x4200000000000000000000000000000000000006);
    address public POOL = address(0xd652C5425aea2Afd5fb142e120FeCf79e18fafc3);
    address public wethWhale = address(0xcDAC0d6c6C59727a65F871236188350531885C43);
    IOracle public baseOracle = IOracle(address(0x6B99b2E868B6E3B8b259E296c4c6aBffbB1AaB94));
    ISwapperFactory public swapperFactory = ISwapperFactory(address(0xa244bbe019cf1BA177EE5A532250be2663Fb55cA));
    uint32 public defaultScaleFactor = uint32(99e4); // 99% (1% discount to swappers)
    address public beefyTokenManager = address(0x3fBD1da78369864c67d62c242d30983d6900c0f0);
    address public beefyZapRouter = address(0x6F19Da51d488926C007B9eBaa5968291a2eC6a63);

    address public alice;

    function setUp() public {
        fork = vm.createFork('base', forkBlock);
        vm.selectFork(fork);
        vm.warp(forkTimestamp);
        alice = makeAddr("Alice");
        prizeCompoundingSwapperHook = new PrizeCompoundingSwapperHook(
            baseOracle,
            swapperFactory,
            defaultScaleFactor
        );
        swapperHelper = new GenericSwapperHelper();
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
        uint256[] memory amounts = prizeCompoundingSwapperHook.getQuoteAmounts(quoteParams);
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
        uint256[] memory amounts = prizeCompoundingSwapperHook.getQuoteAmounts(quoteParams);
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
        uint256[] memory amounts = prizeCompoundingSwapperHook.getQuoteAmounts(quoteParams);
        assertApproxEqAbs(amounts[0], 2291e6, 10e6);
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
        uint256[] memory amounts = prizeCompoundingSwapperHook.getQuoteAmounts(quoteParams);
        assertApproxEqAbs(amounts[0], 2291e6, 10e6);
    }

    function testSwapWethToPrzWeth() external {
        // Set a new swapper on the hook
        ISwapper swapper = prizeCompoundingSwapperHook.setSwapper(address(przWETH));
        assertEq(swapper.tokenToBeneficiary(), address(przWETH));
        assertEq(prizeCompoundingSwapperHook.swappers(address(this)), address(swapper));

        // Simulate a prize being won
        uint256 prizeAmount = 1e18;
        vm.startPrank(wethWhale);
        (address prizeRecipient,) = prizeCompoundingSwapperHook.beforeClaimPrize(address(this), 0, 0, 0, address(0));
        assertEq(prizeRecipient, address(swapper));
        IERC20(WETH).transfer(prizeRecipient, prizeAmount);
        vm.stopPrank();

        // Initiate the flash swap by instructing it to deposit to przWETH
        swapperHelper.flashSwap(
            swapper,
            FlashInfo({
                profitRecipient: alice,
                tokenToSwap: WETH,
                amountToSwap: uint128(prizeAmount),
                minTokenToSwapProfit: 0,
                minTokenToBeneficiaryProfit: prizeAmount / 100, // 1%
                approveTo: address(0),
                callTarget: address(przWETH),
                callData: abi.encodeWithSelector(IERC4626.deposit.selector, prizeAmount, address(swapperHelper))
            })
        );

        assertEq(IERC20(WETH).balanceOf(address(swapperHelper)), 0, "no more WETH in swapper helper");
        assertEq(przWETH.balanceOf(address(swapperHelper)), 0, "no more przWETH in swapper helper");

        assertEq(IERC20(WETH).balanceOf(address(swapper)), 0, "no more WETH in swapper");
        assertEq(przWETH.balanceOf(address(swapper)), 0, "no more przWETH in swapper");

        assertEq(IERC20(WETH).balanceOf(address(alice)), 0, "no WETH sent to alice");
        assertEq(przWETH.balanceOf(address(alice)), prizeAmount / 100, "1% of przWETH sent to alice");

        assertEq(IERC20(WETH).balanceOf(address(this)), 0, "no WETH sent to winner");
        assertEq(przWETH.balanceOf(address(this)), prizeAmount - (prizeAmount / 100), "rest of prize amount sent to winner");
    }

    function testSwapWethToPrzUsdc() external {
        // Set a new swapper on the hook
        ISwapper swapper = prizeCompoundingSwapperHook.setSwapper(address(przUSDC));
        assertEq(swapper.tokenToBeneficiary(), address(przUSDC));
        assertEq(prizeCompoundingSwapperHook.swappers(address(this)), address(swapper));

        // Simulate a prize being won
        uint256 prizeAmount = 8e14;
        vm.startPrank(wethWhale);
        (address prizeRecipient,) = prizeCompoundingSwapperHook.beforeClaimPrize(address(this), 0, 0, 0, address(0));
        assertEq(prizeRecipient, address(swapper));
        IERC20(WETH).transfer(prizeRecipient, prizeAmount);
        vm.stopPrank();

        // Use pre-simulated beefy swap router swap in the flash info
        swapperHelper.flashSwap(
            swapper,
            FlashInfo({
                profitRecipient: alice,
                tokenToSwap: WETH,
                amountToSwap: uint128(prizeAmount),
                minTokenToSwapProfit: 0,
                minTokenToBeneficiaryProfit: 0.01e6, // 1% of $1 worth of ETH should be over $0.01 of USDC
                approveTo: beefyTokenManager,
                callTarget: beefyZapRouter,
                callData: abi.encodePacked(
                    hex"f41b2db6000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000",
                    address(swapperHelper),
                    hex"000000000000000000000000",
                    address(swapperHelper),
                    hex"000000000000000000000000000000000000000000000000000000000000000100000000000000000000000042000000000000000000000000000000000000060000000000000000000000000000000000000000000000000002d79883d200000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000420000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f5c2b379b88499ac2b997db583f8079503f25b900000000000000000000000000000000000000000000000000000000001bc5ae000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000006a00000000000000000000000006a000f20005980200259b80c51020030400010680000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000544e3ead59e0000000000000000000000003800091020a00290f20606b000000000e38c33ef0000000000000000000000004200000000000000000000000000000000000006000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000002d79883d2000000000000000000000000000000000000000000000000000000000000001bc5af00000000000000000000000000000000000000000000000000000000001c0d7f6be459e5f88448e28832993c215d8fc40000000000000000000000000128668700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000636162616e6110000000000000000000000000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000003a000000000000000000000000000000160000000000000010c0000000000000e101e891c9f96dca29da8b97be3403d16135ebe80280000014000040000ff00000300000000000000000000000000000000000000000000000000000000f41766d8000000000000000000000000000000000000000000000000000105ef39b20000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000a00000000000000000000000006a000f20005980200259b80c51020030400010680000000000000000000000000000000000000000000000000000000066db2a6f00000000000000000000000000000000000000000000000000000000000000010000000000000000000000004200000000000000000000000000000000000006000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000190042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb000000000000000000000000994c90f2e654b282e24a1b7d00ee12e82408312c0000000000000000000000000000000000000000000000000001d1a94a200000994c90f2e654b282e24a1b7d00ee12e82408312c000001200024000020000003000000000000000000000000000000000000000000000000000000003eece7db0000000000000000000000006a000f20005980200259b80c51020030400010680000000000000000000000000000000000000000000000000001d1a94a20000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc500000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000004200000000000000000000000000000000000006ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000007f5c2b379b88499ac2b997db583f8079503f25b900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000446e553f6500000000000000000000000000000000000000000000000000000000000000000000000000000000000000006f19da51d488926c007b9ebaa5968291a2ec6a63000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000000000000000004"
                )
            })
        );

        assertEq(IERC20(WETH).balanceOf(address(swapperHelper)), 0, "no more WETH in swapper helper");
        assertEq(przUSDC.balanceOf(address(swapperHelper)), 0, "no more przUSDC in swapper helper");

        assertEq(IERC20(WETH).balanceOf(address(swapper)), 0, "no more WETH in swapper");
        assertEq(przUSDC.balanceOf(address(swapper)), 0, "no more przUSDC in swapper");

        assertEq(IERC20(WETH).balanceOf(address(alice)), 0, "no WETH sent to alice");
        assertGe(przUSDC.balanceOf(address(alice)), 0.01e6, "1% of przUSDC sent to alice");

        assertEq(IERC20(WETH).balanceOf(address(this)), 0, "no WETH sent to winner");
        assertGe(przUSDC.balanceOf(address(this)), 1.7e6, "rest of prize amount sent to winner");
    }

    function testOverrideSwapper() external {
        // Set a new swapper on the hook
        ISwapper swapper1 = prizeCompoundingSwapperHook.setSwapper(address(przUSDC));
        assertEq(prizeCompoundingSwapperHook.swappers(address(this)), address(swapper1));
        assertEq(swapper1.owner(), address(prizeCompoundingSwapperHook));

        // Override the swapper and claim ownership of the old one
        ISwapper swapper2 = prizeCompoundingSwapperHook.setSwapper(address(przWETH));
        assertEq(prizeCompoundingSwapperHook.swappers(address(this)), address(swapper2));
        assertNotEq(address(swapper1), address(swapper2));

        assertEq(swapper1.owner(), address(this));
        assertEq(swapper2.owner(), address(prizeCompoundingSwapperHook));
    }

}
