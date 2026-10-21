// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WindowShopperToken} from "../src/WindowShopperToken.sol";

/// @notice Drives the token with bounded transfers, approvals and transferFroms among a fixed set of
/// actors, and keeps a ghost ledger of what every balance and allowance should be.
contract WindowShopperHandler is Test {
    WindowShopperToken public immutable token;
    address[] internal actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostSucceeded;
    uint256 public ghostReverted;
    uint256 public ghostUnexpected;

    constructor(WindowShopperToken token_, address[] memory actors_, address holder) {
        token = token_;
        actors = actors_;
        ghostBalance[holder] = token_.balanceOf(holder);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = ghostBalance[from];
        // Mostly in range, sometimes one past the balance to exercise the failure path.
        amount = bound(amount, 0, bal + 1);

        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            if (!ok || amount > bal) ++ghostUnexpected;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ++ghostSucceeded;
        } catch (bytes memory reason) {
            bytes memory expected =
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, bal, amount);
            if (amount <= bal || keccak256(reason) != keccak256(expected)) ++ghostUnexpected;
            ++ghostReverted;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        amount = infinite ? type(uint256).max : bound(amount, 0, token.totalSupply() + 1);

        vm.prank(owner);
        try token.approve(spender, amount) returns (bool ok) {
            if (!ok) ++ghostUnexpected;
            ghostAllowance[owner][spender] = amount;
            ++ghostSucceeded;
        } catch {
            ++ghostUnexpected;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = ghostBalance[from];
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = bal < allowed ? bal : allowed;
        amount = bound(amount, 0, cap + 1);

        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            if (!ok || amount > bal || amount > allowed) ++ghostUnexpected;
            if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ++ghostSucceeded;
        } catch (bytes memory reason) {
            // OpenZeppelin spends the allowance before moving the balance, so allowance is checked first.
            bytes memory expected = amount > allowed
                ? abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
                : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, bal, amount);
            if (amount <= cap || keccak256(reason) != keccak256(expected)) ++ghostUnexpected;
            ++ghostReverted;
        }
    }

    /// @notice Calls that must never succeed: transfers to the zero address and approvals of it.
    function zeroAddressCall(uint256 fromSeed, uint256 amount, bool viaApprove) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        if (viaApprove) {
            try token.approve(address(0), amount) {
                ++ghostUnexpected;
            } catch {
                ++ghostReverted;
            }
        } else {
            try token.transfer(address(0), amount) {
                ++ghostUnexpected;
            } catch {
                ++ghostReverted;
            }
        }
    }
}

contract WindowShopperTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant DEPLOYER = address(0xFAC7);

    WindowShopperToken internal token;
    WindowShopperHandler internal handler;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new WindowShopperToken();

        address[] memory actors = new address[](5);
        actors[0] = DEPLOYER;
        actors[1] = address(0xA11CE);
        actors[2] = address(0xB0B);
        actors[3] = address(0xCA201);
        actors[4] = address(0xDA7E);

        handler = new WindowShopperHandler(token, actors, DEPLOYER);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_supplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += token.balanceOf(handler.actorAt(i));
        }
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchGhostLedger() public view {
        for (uint256 i; i < handler.actorCount(); ++i) {
            address a = handler.actorAt(i);
            assertEq(token.balanceOf(a), handler.ghostBalance(a));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchGhostLedger() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < n; ++j) {
                address o = handler.actorAt(i);
                address s = handler.actorAt(j);
                assertEq(token.allowance(o, s), handler.ghostAllowance(o, s));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_everyCallBehavedAsSpecified() public view {
        assertEq(handler.ghostUnexpected(), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "IMDwindowshopper");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
    }
}
