// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";

import { PrizeCompoundingHook, PrizeVaultFactory, PrizeVault, IERC20 } from "src/prize-hooks/examples/prize-compounding/PrizeCompoundingHook.sol";
import { PrizeHooks } from "pt-v5-vault/interfaces/IPrizeHooks.sol";

contract PrizeCompoundingHookTest is Test {

    uint256 fork;
    uint256 forkBlock = 119156907;
    uint256 forkTimestamp = 1713912600;

    PrizeCompoundingHook public prizeComp;
    PrizeVaultFactory public prizeVaultFactory = PrizeVaultFactory(address(0xF0F151494658baE060034c8f4f199F74910ea806));
    PrizeVault public przWETH = PrizeVault(address(0x2998c1685E308661123F64B333767266035f5020));
    address public przWETHWhale = address(0xfB424B3c08e5D1205C66d5140781BD718f7F9860);
    PrizeVault public przPOOL = PrizeVault(address(0xa52e38a9147f5eA9E0c5547376c21c9E3F3e5e1f));
    uint8 public winningTier = 3;
    address public przPoolWinner = address(0x20c7b705B9312daE30B5A96A61ec6013225595D4);
    uint32 public przPoolWinningPrizeIndex = 17;
    address public przWethWinner = address(0xa184aa8488908b43cCf43b5Ef13Ae528693Dfd00);
    uint32 public przWethWinningPrizeIndex = 49;
    uint256 public przWethPrizeAmount = 276252643036572;

    function setUp() public {
        fork = vm.createFork('optimism', forkBlock);
        vm.selectFork(fork);
        vm.warp(forkTimestamp);
        prizeComp = new PrizeCompoundingHook(przWETH, prizeVaultFactory, 50, 50);

        // przPOOL was not deployed by the factory, so we need to trust it separately
        prizeComp.grantRole(prizeComp.TRUSTED_VAULT_ROLE(), address(przPOOL));
    }

    function testConstructorSetsVars() public {
        assertEq(prizeComp.rewardFee(), 50);
        assertEq(prizeComp.liquidityFee(), 50);
        assertEq(address(prizeComp.trustedPrizeVaultFactory()), address(prizeVaultFactory));
        assertEq(address(prizeComp.prizeVault()), address(przWETH));
        assertEq(address(prizeComp.prizeToken()), przWETH.asset());
    }

    function testConstructorSetsAdminRole() public {
        assertEq(prizeComp.hasRole(prizeComp.DEFAULT_ADMIN_ROLE(), address(this)), true);
    }

    function testConstructorMaxFee() public {
        vm.expectRevert(abi.encodeWithSelector(PrizeCompoundingHook.MaxFeeExceeded.selector, 101, 100));
        new PrizeCompoundingHook(przWETH, prizeVaultFactory, 51, 50);

        vm.expectRevert(abi.encodeWithSelector(PrizeCompoundingHook.MaxFeeExceeded.selector, 101, 100));
        new PrizeCompoundingHook(przWETH, prizeVaultFactory, 50, 51);

        vm.expectRevert(abi.encodeWithSelector(PrizeCompoundingHook.MaxFeeExceeded.selector, 101, 100));
        new PrizeCompoundingHook(przWETH, prizeVaultFactory, 101, 0);

        vm.expectRevert(abi.encodeWithSelector(PrizeCompoundingHook.MaxFeeExceeded.selector, 101, 100));
        new PrizeCompoundingHook(przWETH, prizeVaultFactory, 0, 101);

        // does not revert:
        new PrizeCompoundingHook(przWETH, prizeVaultFactory, 0, 100);
        new PrizeCompoundingHook(przWETH, prizeVaultFactory, 100, 0);
        new PrizeCompoundingHook(przWETH, prizeVaultFactory, 0, 0);
        new PrizeCompoundingHook(przWETH, prizeVaultFactory, 1, 1);
    }

    function testConstructorPrizeTokenDepositAsset() public {
        // cannot auto-compound WETH into przPOOL since assets don't match
        vm.expectRevert(abi.encodeWithSelector(PrizeCompoundingHook.PrizeTokenNotDepositAsset.selector, przWETH.asset(), przPOOL.asset()));
        new PrizeCompoundingHook(przPOOL, prizeVaultFactory, 0, 0);
    }

    function testBeforeClaimPrize() public {
        (address recipient, bytes memory data) = prizeComp.beforeClaimPrize(address(0), 0, 0, 0, address(0));
        assertEq(recipient, address(prizeComp));
        assertEq(data, "");
    }

    function testAfterClaimPrizeNotTrustedPrizeVault() public {
        vm.expectRevert(abi.encodeWithSelector(PrizeCompoundingHook.CallerNotTrustedPrizeVault.selector, address(this)));
        prizeComp.afterClaimPrize(
            przPoolWinner,
            winningTier,
            przPoolWinningPrizeIndex,
            1,
            address(prizeComp),
            ""
        );
    }

    function testAfterClaimPrizeDidNotReceivePrize() public {
        vm.startPrank(address(przPOOL));
        vm.expectRevert(abi.encodeWithSelector(PrizeCompoundingHook.DidNotReceivePrize.selector, address(this)));
        prizeComp.afterClaimPrize(
            przPoolWinner,
            winningTier,
            przPoolWinningPrizeIndex,
            1,
            address(this),
            ""
        );
        vm.stopPrank();
    }

    function testAfterClaimPrizeZeroPrizeAmount() public {
        vm.startPrank(address(przPOOL));
        // nothing happens
        prizeComp.afterClaimPrize(
            przPoolWinner,
            winningTier,
            przPoolWinningPrizeIndex,
            0,
            address(prizeComp),
            ""
        );
        vm.stopPrank();
    }

    function testIsTrustedVault() public {
        assertEq(prizeComp.isTrustedVault(address(przWETH)), true);
        assertEq(prizeComp.isTrustedVault(address(przPOOL)), true);
        assertEq(prizeComp.isTrustedVault(address(this)), false);

        prizeComp.grantRole(prizeComp.TRUSTED_VAULT_ROLE(), address(this));
        assertEq(prizeComp.isTrustedVault(address(this)), true);
    }

    function testCalculateFee() public {
        assertEq(prizeComp.calculateFee(10000), 100);
        assertEq(prizeComp.calculateFee(100), 1);
        assertEq(prizeComp.calculateFee(99), 0); // too small of precision
    }

    function testCalculateRecycleReward() public {
        assertEq(prizeComp.calculateRecycleReward(10000), 50);
        assertEq(prizeComp.calculateRecycleReward(9999), 49);
        assertEq(prizeComp.calculateRecycleReward(100), 0); // too small of precision
        assertEq(prizeComp.calculateRecycleReward(99), 0); // too small of precision
    }

    function testCurrentRecycleReward() public {
        _provideLiquidity(1e18);

        assertEq(prizeComp.currentRecycleReward(), 0);

        _compoundPrize();

        assertEq(prizeComp.currentRecycleReward(), przWethPrizeAmount / 200);
    }

    function testCurrentRecycleRewardNoLiquidity() public {
        assertEq(prizeComp.currentRecycleReward(), 0);
        uint256 prizeTokenBalanceBefore = prizeComp.prizeToken().balanceOf(przWethWinner);
        _compoundPrize();
        assertEq(prizeComp.prizeToken().balanceOf(przWethWinner) - prizeTokenBalanceBefore, przWethPrizeAmount);
        assertEq(prizeComp.currentRecycleReward(), 0);
    }

    function testRecyclePrizeTokens() public {
        _provideLiquidity(1e18);
        uint256 przWethBalanceBefore = przWETH.balanceOf(przWethWinner);
        _compoundPrize();
        assertEq(przWETH.balanceOf(przWethWinner) - przWethBalanceBefore, przWethPrizeAmount - prizeComp.calculateFee(przWethPrizeAmount));

        uint256 recycleReward = prizeComp.currentRecycleReward();
        uint256 liquidityReward = przWethPrizeAmount / 200;
        assertEq(prizeComp.prizeToken().balanceOf(address(prizeComp)), przWethPrizeAmount);
        assertEq(przWETH.balanceOf(address(prizeComp)), 1e18 - przWethPrizeAmount + prizeComp.calculateFee(przWethPrizeAmount));

        assertEq(prizeComp.prizeToken().balanceOf(address(this)), 0);
        prizeComp.recyclePrizeTokens(address(this));
        assertEq(prizeComp.prizeToken().balanceOf(address(this)), recycleReward);

        assertEq(prizeComp.prizeToken().balanceOf(address(prizeComp)), 0);
        assertApproxEqAbs(przWETH.balanceOf(address(prizeComp)), 1e18 + liquidityReward, 1);
    }

    function testWithdrawTokenBalanceNotAdmin() public {
        vm.startPrank(przWethWinner);
        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", przWethWinner, prizeComp.DEFAULT_ADMIN_ROLE()));
        prizeComp.withdrawTokenBalance(IERC20(address(przWETH)), address(this), 1e18);
        vm.stopPrank();
    }

    function testWithdrawTokenBalancePrzWeth() public {
        _provideLiquidity(1e18);
        prizeComp.withdrawTokenBalance(IERC20(address(przWETH)), address(this), 1e18);
        assertEq(przWETH.balanceOf(address(this)), 1e18);
    }

    function testWithdrawTokenBalancePrzWethPartial() public {
        _provideLiquidity(1e18);
        prizeComp.withdrawTokenBalance(IERC20(address(przWETH)), address(this), 1e9);
        assertEq(przWETH.balanceOf(address(this)), 1e9);
        assertEq(przWETH.balanceOf(address(prizeComp)), 1e18 - 1e9);
    }

    function _provideLiquidity(uint256 _amount) internal {
        vm.startPrank(przWETHWhale);
        przWETH.transfer(address(prizeComp), _amount);
        vm.stopPrank();
    }

    function _compoundPrize() internal {
        vm.startPrank(przWethWinner);
        przWETH.setHooks(PrizeHooks({
            useBeforeClaimPrize: true,
            useAfterClaimPrize: true,
            implementation: prizeComp
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
