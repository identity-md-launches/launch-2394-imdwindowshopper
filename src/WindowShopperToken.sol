// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title IMDwindowshopper (WWW)
/// @notice Stop window shopping. See everything first. @windowshoppermd
/// @dev A fixed-supply ERC-20. The whole supply is minted once, in the constructor, to the deployer
/// (on launch, the IMD factory, which distributes it). There is no owner, no mint, no pause, no
/// blacklist and no transfer fee: every transfer moves exactly the amount it names.
contract WindowShopperToken is ERC20 {
    /// @notice Token name returned by `name()`.
    string public constant TOKEN_NAME = "IMDwindowshopper";
    /// @notice Token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "WWW";
    /// @notice The fixed total supply: 1,000,000,000 tokens with 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
