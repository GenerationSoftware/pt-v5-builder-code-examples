// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin/mocks/ERC20Mock.sol";

import { PrizeBoostHook } from "src/prize-hooks/examples/prize-boost/PrizeBoostHook.sol";

contract PrizeBoostHookTest is Test {
    event PrizeBoosted(address indexed recipient, address indexed vault, uint256 boostAmount, uint8 tier);

    PrizeBoostHook public prizeBoostHook;
    ERC20Mock public boostToken;
    address public alice;
    uint256 public boostAmount;
    uint8 public maxTier;

    function setUp() public {
        boostToken = new ERC20Mock();
        alice = makeAddr("alice");
        boostAmount = 1e18;
        maxTier = 3;
        prizeBoostHook = new PrizeBoostHook(address(this), boostToken, boostAmount, maxTier);
    }

    function testHappyPath() public {
        boostToken.mint(address(prizeBoostHook), boostAmount * 10);

        assertEq(boostToken.balanceOf(alice), 0);
        assertEq(boostToken.balanceOf(address(prizeBoostHook)), boostAmount * 10);

        vm.expectEmit();
        emit PrizeBoosted(alice, address(this), boostAmount, maxTier);

        prizeBoostHook.afterClaimPrize(alice, maxTier, 0, 0, alice);

        assertEq(boostToken.balanceOf(alice), boostAmount);
        assertEq(boostToken.balanceOf(address(prizeBoostHook)), boostAmount * 9);
    }

    function testNothingHappens_notVault() public {
        boostToken.mint(address(prizeBoostHook), boostAmount * 10);

        assertEq(boostToken.balanceOf(alice), 0);
        assertEq(boostToken.balanceOf(address(prizeBoostHook)), boostAmount * 10);

        vm.startPrank(alice);
        prizeBoostHook.afterClaimPrize(alice, maxTier, 0, 0, alice);
        vm.stopPrank();

        assertEq(boostToken.balanceOf(alice), 0);
        assertEq(boostToken.balanceOf(address(prizeBoostHook)), boostAmount * 10);
    }

    function testNothingHappens_tierGtMax() public {
        boostToken.mint(address(prizeBoostHook), boostAmount * 10);

        assertEq(boostToken.balanceOf(alice), 0);
        assertEq(boostToken.balanceOf(address(prizeBoostHook)), boostAmount * 10);

        prizeBoostHook.afterClaimPrize(alice, maxTier + 1, 0, 0, alice);

        assertEq(boostToken.balanceOf(alice), 0);
        assertEq(boostToken.balanceOf(address(prizeBoostHook)), boostAmount * 10);
    }

    function testNothingHappens_notEnoughTokens() public {
        boostToken.mint(address(prizeBoostHook), boostAmount - 1);

        assertEq(boostToken.balanceOf(alice), 0);
        assertEq(boostToken.balanceOf(address(prizeBoostHook)), boostAmount - 1);

        prizeBoostHook.afterClaimPrize(alice, maxTier, 0, 0, alice);

        assertEq(boostToken.balanceOf(alice), 0);
        assertEq(boostToken.balanceOf(address(prizeBoostHook)), boostAmount - 1);
    }
}
