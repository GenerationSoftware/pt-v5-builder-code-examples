// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { NftChanceBoosterHook, PrizePool } from "src/prize-hooks/examples/nft-chance-booster/NftChanceBoosterHook.sol";
import { PrizeHooks, IPrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { ERC721ConsecutiveMock } from "openzeppelin-v5/mocks/token/ERC721ConsecutiveMock.sol";

contract NftChanceBoosterHookTest is Test {

    event BoostedVaultWithPrize(address indexed prizePool, address indexed boostedVault, uint256 prizeAmount, uint256 pickAttempts);
    event PrizeWonByNftHolder(address indexed nftWinner, address indexed vault, address indexed donor, uint8 tier, uint32 prizeIndex, uint256 prizeAmount);

    uint256 fork;
    uint256 forkBlock = 17582112;
    uint256 forkTimestamp = 1721996771;
    uint256 randomNumber = 282830497779024192640724388550852704286534307968011569641355386343626319848;
    uint96 nftIdOffset = 5;
    uint256 minTwab = 1e18;
    address[] holders;
    uint96[] holderNumTokens;
    address[] diverseHolders;
    uint96[] diverseHoldersNumTokens;

    NftChanceBoosterHook public nftBooster;
    ERC721ConsecutiveMock public nft;
    PrizePool public prizePool = PrizePool(address(0x45b2010d8A4f08b53c9fa7544C51dFd9733732cb));

    function setUp() public {
        fork = vm.createFork('base', forkBlock);
        vm.selectFork(fork);
        vm.warp(forkTimestamp);

        holders.push(makeAddr('bob'));
        holders.push(makeAddr('alice'));
        holderNumTokens.push(9);
        holderNumTokens.push(1);

        for (uint256 i = 0; i < 100; i++) {
            diverseHolders.push(makeAddr(string(abi.encode(i))));
            diverseHoldersNumTokens.push(1);
        }

        nft = new ERC721ConsecutiveMock("Test NFT", "TNFT", nftIdOffset, holders, holders, holderNumTokens);

        nftBooster = new NftChanceBoosterHook(nft, prizePool, address(this), minTwab, nftIdOffset, nftIdOffset + 9);
    }

    function testRecipientIsPrizePoolIfNotEligible() public {
        address bob = holders[0];
        address alice = holders[1];
        assertEq(prizePool.twabController().delegateBalanceOf(address(this), bob), 0);
        assertEq(prizePool.twabController().delegateBalanceOf(address(this), alice), 0);
        // check a bunch of numbers and ensure there are no valid winners selected
        for (uint256 i = 0; i < 1000; i++) {
            vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.getWinningRandomNumber.selector), abi.encode(randomNumber + i));
            (address recipient, bytes memory hookData) = callBeforeClaimPrize(0, 0);
            assertEq(recipient, address(prizePool));
            (uint256 pickAttempts) = abi.decode(hookData, (uint256));
            assertGt(pickAttempts, 0);
            assertLt(pickAttempts, 10); // probably won't ever exceed 10 pick attempts, but this is not strictly required
        }
    }

    function testRecipientIsNotPrizePoolIfEligible() public {
        address bob = holders[0];
        address alice = holders[1];
        vm.warp(prizePool.drawOpensAt(1));
        prizePool.twabController().mint(bob, 1e18);
        prizePool.twabController().mint(alice, 1e18);
        vm.warp(forkTimestamp);
        assertEq(prizePool.twabController().delegateBalanceOf(address(this), bob), 1e18);
        assertEq(prizePool.twabController().delegateBalanceOf(address(this), alice), 1e18);
        // check a bunch of numbers and ensure there are no valid winners selected
        uint256 numBobWins;
        uint256 numAliceWins;
        for (uint256 i = 0; i < 1000; i++) {
            vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.getWinningRandomNumber.selector), abi.encode(randomNumber + i));
            (address recipient, bytes memory hookData) = callBeforeClaimPrize(0, 0);
            if (recipient == address(nftBooster)) {
                (address winner) = abi.decode(hookData, (address));
                if (winner == bob) numBobWins++;
                else if (winner == alice) numAliceWins++;
            }
        }
        assertGt(numBobWins, 800);
        assertGt(numAliceWins, 50);
    }

    function testRecipientRetries() public {
        address bob = holders[0];
        address alice = holders[1];
        vm.warp(prizePool.drawOpensAt(1));
        prizePool.twabController().mint(bob, 1e18);
        vm.warp(forkTimestamp);
        assertEq(prizePool.twabController().delegateBalanceOf(address(this), bob), 1e18);
        // Alice was not minted any balance, so she will not be eligible, but since bob has 5 tokens and alice has 1,
        // it should still be very likely that bob is selected every time given 3 picks.
        assertEq(prizePool.twabController().delegateBalanceOf(address(this), alice), 0);
        // check a bunch of numbers and ensure there are no valid winners selected
        uint256 numBobWins;
        uint256 numAliceWins;
        for (uint256 i = 0; i < 1000; i++) {
            vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.getWinningRandomNumber.selector), abi.encode(randomNumber + i));
            (address recipient, bytes memory hookData) = callBeforeClaimPrize(0, 0);
            if (recipient == address(nftBooster)) {
                (address winner) = abi.decode(hookData, (address));
                if (winner == bob) numBobWins++;
                else if (winner == alice) numAliceWins++;
            }
        }
        assertGt(numBobWins, 900);
        assertEq(numAliceWins, 0);
    }

    function testRetriesDoesNotRevert() public {
        nft = new ERC721ConsecutiveMock("Test NFT", "TNFT", nftIdOffset, diverseHolders, diverseHolders, diverseHoldersNumTokens);
        nftBooster = new NftChanceBoosterHook(nft, prizePool, address(this), minTwab, nftIdOffset, nftIdOffset + diverseHolders.length - 1);
        
        // check a bunch of numbers and ensure there are no valid winners selected
        for (uint256 i = 0; i < 1000; i++) {
            vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.getWinningRandomNumber.selector), abi.encode(randomNumber + i));
            (address recipient, bytes memory hookData) = callBeforeClaimPrize(0, 0);
            assertEq(recipient, address(prizePool));
            (uint256 pickAttempts) = abi.decode(hookData, (uint256));
            assertGt(pickAttempts, 0);
            assertLt(pickAttempts, 10); // probably won't ever exceed 10 pick attempts, but this is not strictly required
        }
    }

    function testAfterClaimPrizeRedirectsPrize() public {
        address alice = holders[1];
        deal(address(prizePool.prizeToken()), address(nftBooster), 1e18);
        assertEq(prizePool.prizeToken().balanceOf(alice), 0);
        assertEq(prizePool.prizeToken().balanceOf(address(nftBooster)), 1e18);
        vm.expectEmit();
        emit PrizeWonByNftHolder(alice, address(this), address(1), 2, 3, 1e18);
        (bool success,) = address(nftBooster).call{ gas: 150_000 }(abi.encodeWithSelector(IPrizeHooks.afterClaimPrize.selector, address(1), 2, 3, 1e18, address(nftBooster), abi.encode(address(alice))));
        require(success, "afterClaimPrize failed");
        assertEq(prizePool.prizeToken().balanceOf(alice), 1e18);
        assertEq(prizePool.prizeToken().balanceOf(address(nftBooster)), 0);
    }

    function testAfterClaimPrizeContributesPrize() public {
        deal(address(prizePool.prizeToken()), address(prizePool), 1e18 + prizePool.prizeToken().balanceOf(address(prizePool)));
        vm.expectEmit();
        emit BoostedVaultWithPrize(address(prizePool), address(this), 1e18, 5);
        (bool success,) = address(nftBooster).call{ gas: 150_000 }(abi.encodeWithSelector(IPrizeHooks.afterClaimPrize.selector, address(1), 2, 3, 1e18, address(prizePool), abi.encode(uint256(5))));
        require(success, "afterClaimPrize failed");
        assertEq(prizePool.getContributedBetween(address(this), prizePool.getOpenDrawId(), prizePool.getOpenDrawId()), 1e18);
    }

    function callBeforeClaimPrize(uint8 tier, uint32 prizeIndex) internal returns (address recipient, bytes memory hookData) {
        (bool success, bytes memory data) = address(nftBooster).call{ gas: 150_000 }(abi.encodeWithSelector(IPrizeHooks.beforeClaimPrize.selector, address(0), tier, prizeIndex, 0, address(0)));
        require(success, "beforeClaimPrize failed");
        (recipient, hookData) = abi.decode(data, (address,bytes));
        // if (hookData.length > 0) {
        //     uint256 pickAttempt = abi.decode(hookData, (uint256));
        //     if (pickAttempt > 0) {
        //         console2.log("pick attempt", pickAttempt);
        //     }
        // }
    }

}
