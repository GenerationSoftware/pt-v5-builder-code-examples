// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";

import { DailyDoubleHook, PrizePool } from "src/prize-hooks/examples/daily-double/DailyDoubleHook.sol";
import { PrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";

contract DailyDoubleHookTest is Test {

    uint256 fork;
    uint256 forkBlock = 119156907;
    uint256 forkTimestamp = 1713912600;

    DailyDoubleHook public dailyDouble;
    PrizeVault public przWETH = PrizeVault(address(0x2998c1685E308661123F64B333767266035f5020));
    uint8 public winningTier = 3;
    address public przWethWinner = address(0xa184aa8488908b43cCf43b5Ef13Ae528693Dfd00);
    uint32 public przWethWinningPrizeIndex = 49;
    uint256 public przWethPrizeAmount = 276252643036572;

    function setUp() public {
        fork = vm.createFork('optimism', forkBlock);
        vm.selectFork(fork);
        vm.warp(forkTimestamp);
        dailyDouble = new DailyDoubleHook(przWETH.prizePool(), address(this));
    }

    function testDailyDouble() public {
        _claimPrize();
        assertEq(dailyDouble.prizePool().getContributedBetween(address(this), 6, 6), przWethPrizeAmount);
    }

    function _claimPrize() internal {
        vm.startPrank(przWethWinner);
        przWETH.setHooks(PrizeHooks({
            useBeforeClaimPrize: true,
            useAfterClaimPrize: true,
            implementation: dailyDouble
        }));
        vm.stopPrank();

        address[] memory winners = new address[](1);
        winners[0] = przWethWinner;
        uint32[][] memory prizeIndices = new uint32[][](1);
        uint32[] memory prizeIndices0 = new uint32[](1);
        prizeIndices0[0] = przWethWinningPrizeIndex;
        prizeIndices[0] = prizeIndices0;

        (bool success, bytes memory data) = przWETH.claimer().call(
            abi.encodeWithSignature(
                "claimPrizes(address,uint8,address[],uint32[][],address,uint256)",
                address(przWETH),
                winningTier,
                winners,
                prizeIndices,
                address(this),
                1 // min fee per claim
            )
        );
        if (!success) {
            revert("claimPrizes failed");
        }
        if (abi.decode(data, (uint256)) == 0) {
            revert("no claims");
        }
    }

}
