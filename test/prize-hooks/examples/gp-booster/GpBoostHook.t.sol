// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";

import { GpBoostHook, PrizePool } from "src/prize-hooks/examples/gp-booster/GpBoostHook.sol";
import { PrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";

contract GpBoostHookTest is Test {

    uint256 fork;
    uint256 forkBlock = 118900269;
    uint256 forkTimestamp = 1713399313;
    uint256 randomNumber = 282830497779024192640724388550852704286534307968011569641355386343626319848;

    GpBoostHook public gpBooster;
    PrizePool public prizePool = PrizePool(address(0xF35fE10ffd0a9672d0095c435fd8767A7fe29B55));

    function setUp() public {
        fork = vm.createFork('optimism', forkBlock);
        vm.selectFork(fork);
        vm.warp(forkTimestamp);
        gpBooster = new GpBoostHook(prizePool, address(this));
        deal(address(prizePool.prizeToken()), address(this), 1e18);
        prizePool.prizeToken().approve(address(gpBooster), type(uint256).max);
    }

    function testAllPrizes() public {
        bool claimedDaily = false;
        bool claimedCanary = false;
        bool triedToClaimGp = false;
        while (!(claimedDaily && claimedCanary && triedToClaimGp)) {
            uint24 openDrawId = prizePool.getOpenDrawId();
            require(openDrawId < 1000, "too many draws passed");

            // make a small contribution
            gpBooster.contributePrizeTokens(1e15);
            assertGe(prizePool.getContributedBetween(address(gpBooster), openDrawId, openDrawId), 1e15);

            // warp to next draw
            vm.warp(prizePool.drawClosesAt(openDrawId) + 1);

            // award draw
            vm.startPrank(prizePool.drawManager());
            prizePool.awardDraw(randomNumber);
            randomNumber = uint256(keccak256(abi.encodePacked(randomNumber)));
            vm.stopPrank();

            // check for wins
            if (!claimedDaily) {
                uint256 amount = _claimPrize(1, 0);
                assertEq(prizePool.getContributedBetween(address(gpBooster), openDrawId+1, openDrawId+1), amount);
                claimedDaily = true;
            }
            if (!claimedCanary) {
                uint256 contributedBefore = prizePool.getContributedBetween(address(gpBooster), openDrawId+1, openDrawId+1);
                uint256 amount = _claimPrize(2, 0);
                uint256 contributedAfter = prizePool.getContributedBetween(address(gpBooster), openDrawId+1, openDrawId+1);
                assertEq(amount, 0);
                assertEq(contributedAfter, contributedBefore); // no contribution
                claimedCanary = true;
            }
            if (!triedToClaimGp) {
                if (prizePool.isWinner(address(gpBooster), address(gpBooster), 0, 0)) {
                    vm.expectRevert(abi.encodeWithSelector(GpBoostHook.LeaveTheGpInThePrizePool.selector));
                    _claimPrize(0, 0);
                    triedToClaimGp = true;
                }
            }
        }
    }

    function _claimPrize(uint8 tier, uint32 prizeIndex) internal returns (uint256) {
        uint256 rewardAmount = (tier > 1 ? prizePool.getTierPrizeSize(tier) : 0); // canaries have no prize value
        uint256 prizeAmount = gpBooster.claimPrize(address(gpBooster), tier, prizeIndex, uint96(rewardAmount), address(this));
        return prizeAmount - rewardAmount;
    }

}
