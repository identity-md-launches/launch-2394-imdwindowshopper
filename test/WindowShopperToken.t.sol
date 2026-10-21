// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WindowShopperToken} from "../src/WindowShopperToken.sol";

contract WindowShopperTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    WindowShopperToken internal token;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5BE7D);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new WindowShopperToken();
    }

    // ---------------------------------------------------------------- metadata and supply

    function test_metadata() public view {
        assertEq(token.name(), "IMDwindowshopper");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    function test_mintsWholeSupplyToDeployerOnce() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        WindowShopperToken fresh = new WindowShopperToken();
        assertEq(fresh.balanceOf(ALICE), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_hasNoMintOrAdminEntryPoints() public {
        bytes[6] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("mint(uint256)", 1),
            abi.encodeWithSignature("owner()"),
            abi.encodeWithSignature("transferOwnership(address)", ALICE),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("burnFrom(address,uint256)", DEPLOYER, 1)
        ];
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok, "unexpected admin entry point");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_rejectsEther() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    // ---------------------------------------------------------------- transfer

    function test_transferMovesExactAmount() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(DEPLOYER, ALICE, 123 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 123 ether));
        assertEq(token.balanceOf(ALICE), 123 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_transferZeroAmount() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_selfTransferKeepsBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(DEPLOYER, 10 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_RevertWhen_transferExceedsBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 5 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 5 ether, 6 ether));
        vm.prank(ALICE);
        token.transfer(BOB, 6 ether);
    }

    function test_RevertWhen_transferFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transfer(ALICE, 1);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1 ether);
    }

    // ---------------------------------------------------------------- approve / transferFrom

    function test_approveSetsAllowance() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(DEPLOYER, SPENDER, 50 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.approve(SPENDER, 50 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 50 ether);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 50 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 20 ether));
        assertEq(token.balanceOf(BOB), 20 ether);
        assertEq(token.allowance(DEPLOYER, SPENDER), 30 ether);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, 20 ether);
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max);
    }

    function test_RevertWhen_transferFromWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1 ether));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, 1 ether);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 10 ether, 11 ether)
        );
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, 11 ether);
    }

    function test_RevertWhen_transferFromExceedsBalance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1 ether);
    }

    function test_RevertWhen_approveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
    }

    function test_deployerCannotMoveAHoldersBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(ALICE, DEPLOYER, 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != DEPLOYER);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowance, uint256 amount) public {
        allowance = bound(allowance, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, allowance);
        vm.prank(SPENDER);
        if (amount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowance, amount)
            );
            token.transferFrom(DEPLOYER, BOB, amount);
            assertEq(token.balanceOf(BOB), 0);
        } else {
            token.transferFrom(DEPLOYER, BOB, amount);
            assertEq(token.balanceOf(BOB), amount);
            assertEq(token.allowance(DEPLOYER, SPENDER), allowance - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
