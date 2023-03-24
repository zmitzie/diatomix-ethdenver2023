// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
interface IPool {
    function _userDeposit(uint256 amount) external;
    function _userWithdraw(uint256 dxpAmount) external;
    function _userDepositOnBehalfOf(uint256 amount, address onBehalfOf, address supplier) external;
}