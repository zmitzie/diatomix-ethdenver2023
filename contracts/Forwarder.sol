// SPDX-License-Identifier: Unlicesed
pragma solidity ^0.8.13;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Mintable.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolFactory.sol";

contract Forwarder {

    address private permitUsdcAddress;
    address private aaveUsdcAddress;
    address private poolFactoryAddress;


    constructor(
        address _permitUsdcAddress, 
        address _aaveUsdcAddress,
        address _poolFactoryAddress
    ) {
        permitUsdcAddress = _permitUsdcAddress;
        aaveUsdcAddress = _aaveUsdcAddress;
        poolFactoryAddress = _poolFactoryAddress;
    }

    function depositToPoolDemo(address poolAddress, uint256 amount, address onBehalfOf) public {
        // Verify that pool was deployed from factory
        require(IPoolFactory(poolFactoryAddress).isContractDeployed(poolAddress), "Forwarder: Pool is not deployed from factory");
        IERC20(permitUsdcAddress).transferFrom(onBehalfOf, address(this), amount);
        IERC20Mintable(permitUsdcAddress).burn(address(this), amount);

        IERC20Mintable(aaveUsdcAddress).mint(amount);
        IERC20Mintable(aaveUsdcAddress).approve(poolAddress, amount);
        IPool(poolAddress)._userDepositOnBehalfOf(amount, onBehalfOf, address(this));
    }

    function depositToPool(address poolAddress, uint256 amount, address onBehalfOf) public {
        // Verify that pool was deployed from factory
        require(IPoolFactory(poolFactoryAddress).isContractDeployed(poolAddress), "Forwarder: Pool is not deployed from factory");
        IERC20(permitUsdcAddress).transferFrom(onBehalfOf, address(this), amount);
        IERC20(permitUsdcAddress).approve(poolAddress, amount);
        IPool(poolAddress)._userDepositOnBehalfOf(amount, onBehalfOf, address(this));
    }
}