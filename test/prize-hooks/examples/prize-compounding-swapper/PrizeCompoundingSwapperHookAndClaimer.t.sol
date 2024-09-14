// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import {
    PrizeCompoundingSwapperHookAndClaimer,
    PrizeVault,
    IUniV3Oracle,
    ISwapperFactory,
    ISwapper,
    IUniswapV3Router,
    IERC20,
    QuoteParams,
    QuotePair
} from "src/prize-hooks/examples/prize-compounding-swapper/PrizeCompoundingSwapperHookAndClaimer.sol";
import { PrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";

contract PrizeCompoundingSwapperHookAndClaimerTest is Test {

    uint256 fork;
    uint256 forkBlock = 19424769;
    uint256 forkTimestamp = 1725638885;

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
        uint256[] memory amounts = hookAndClaimer.getQuoteAmounts(quoteParams);
        assertApproxEqAbs(amounts[0], 2291e6, 10e6);
    }

}
