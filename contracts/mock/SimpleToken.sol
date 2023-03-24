// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SimpleToken is Context, ERC20 {
    /**
     * @dev Constructor that gives _msgSender() all of existing tokens.
     */
    constructor () ERC20("SimpleToken", "SIM") {
        _mint(_msgSender(), 1000000000000000000000000000 * (10 ** uint256(decimals())));
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}