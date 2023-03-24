// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
interface IPoolFactory {
    function isContractDeployed(address pool) external returns (bool);
}