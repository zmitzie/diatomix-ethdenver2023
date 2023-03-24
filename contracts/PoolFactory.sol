// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./Pool.sol";

contract PoolFactory is Initializable, OwnableUpgradeable {
    // //using Array for address[];

    address[] private pools;
    mapping(address => bool) public poolsMapper;


    event PoolDeployed(address pool);

    function initialize() public initializer {
        __Ownable_init();
    }

    function createPool(
        address _underlyingAssetAddressA,
        address _underlyingAssetAddressB,
        //address _oracleForAssetA,
        //address _oracleForAssetB,
        uint256 _loanpct,
        uint256 _aaveInterestMode,
        uint256 _assetAZapThreshold,
        uint256 _assetBZapThreshold,
        string memory _name,
        string memory _symbol,
        uint256 _updateInterval
    ) external onlyOwner {
        Pool poolContractInstance = new Pool();
        poolContractInstance.initialize(_underlyingAssetAddressA, _underlyingAssetAddressB, _loanpct, _aaveInterestMode, _assetAZapThreshold, _assetBZapThreshold, _name, _symbol, _updateInterval);
        //Add new instance to array
        pools.push(address(poolContractInstance));
        poolsMapper[address(poolContractInstance)] = true;
        //emit event of new instance created
        emit PoolDeployed(address(poolContractInstance));
    }

    function countPoolInstances() external view returns (uint256) {
        return pools.length;
    }

    function getAllPoolInstances() external view returns (address[] memory) {
        return pools;
    }

    function pushToArray(address _contract) external onlyOwner {
        pools.push(address(_contract));
    }

    function isContractDeployed(address _contract) external returns (bool){
        return poolsMapper[_contract];
    }

    function removePool(uint index) external onlyOwner {
        delete pools[index];
    }
}
