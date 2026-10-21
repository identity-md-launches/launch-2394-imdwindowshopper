// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WindowShopperToken} from "../src/WindowShopperToken.sol";

/// @notice Edge cases not covered by the base suite: zero-address paths of transferFrom, allowance
/// overwrite and exact exhaustion, self-spending, and fuzzed approvals and transfers by non-deployers.
contract WindowShopperTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    WindowShopperToken internal token;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5BE7D);

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new WindowShopperToken();
    }

    function test_supplyIsExactlyOneBillionWholeTokens() public view {
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply() / 10 ** token.decimals(), 1_000_000_000);
        assertEq(token.totalSupply() % 10 ** token.decimals(), 0);
    }

    function test_RevertWhen_transferFromToZeroAddress() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, address(0), 1 ether);
        assertEq(token.allowance(DEPLOYER, SPENDER), 1 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_RevertWhen_transferFromZeroAddressOwner() public {
        // Nobody can hold an allowance from address(0), so the allowance check fails first.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(0), BOB, 1);
    }

    function test_RevertWhen_transferExceedsSupplyByOneWei() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, SUPPLY + 1)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY + 1);
    }

    function test_RevertWhen_transferMaxUint() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, type(uint256).max);
    }

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(DEPLOYER);
        token.approve(SPENDER, 10 ether);
        token.approve(SPENDER, 3 ether);
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, SPENDER), 3 ether);

        vm.prank(DEPLOYER);
        token.approve(SPENDER, 0);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, 1);
    }

    function test_allowanceExhaustsExactlyThenReverts() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 7 ether);
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, 7 ether);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, 1);
    }

    function test_transferFromZeroAmountNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 0));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_ownerNeedsAllowanceToTransferFromSelf() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(DEPLOYER, ALICE, 1);
    }

    function test_allowancesAreIsolatedPerOwnerAndSpender() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 5 ether);
        assertEq(token.allowance(DEPLOYER, ALICE), 0);
        assertEq(token.allowance(SPENDER, DEPLOYER), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_spenderCannotRedirectAllowanceToAnotherOwner() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10 ether);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1 ether);
        assertEq(token.balanceOf(ALICE), 10 ether);
    }

    function test_balanceCanReturnToDeployerAndLeaveAgain() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        vm.prank(ALICE);
        token.transfer(DEPLOYER, SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_rejectsCallsWithUnknownSelectorAndValue() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(token).call{value: 1 ether}(abi.encodeWithSignature("deposit()"));
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveAnyValue(address owner, address spender, uint256 amount) public {
        vm.assume(owner != address(0) && spender != address(0));
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_secondHopTransfer(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, first);

        vm.prank(ALICE);
        if (second > first) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, first, second)
            );
            token.transfer(BOB, second);
            assertEq(token.balanceOf(ALICE), first);
            assertEq(token.balanceOf(BOB), 0);
        } else {
            token.transfer(BOB, second);
            assertEq(token.balanceOf(ALICE), first - second);
            assertEq(token.balanceOf(BOB), second);
        }
        assertEq(token.balanceOf(DEPLOYER) + token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromChecksAllowanceThenBalance(uint256 held, uint256 allowed, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        allowed = bound(allowed, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(SPENDER, allowed);

        vm.prank(SPENDER);
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowed, amount)
            );
            token.transferFrom(ALICE, BOB, amount);
        } else if (amount > held) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
            token.transferFrom(ALICE, BOB, amount);
        } else {
            token.transferFrom(ALICE, BOB, amount);
            assertEq(token.balanceOf(BOB), amount);
            assertEq(token.balanceOf(ALICE), held - amount);
            assertEq(token.allowance(ALICE, SPENDER), allowed - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
