// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
interface IERC20Mintable {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function decimals() external view returns (uint8);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    function mint(uint256 amount) external returns (bool);

    function burn(address from, uint256 amount) external; 
}