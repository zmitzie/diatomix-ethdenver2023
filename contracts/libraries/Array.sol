// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title The following library contains functions that operate on unsigned integer arrays and address arrays
 * @notice This library was not sourced from any external entity or organisation outside Verum Capital
*/
library Array {
     // @dev This function returns the sum elements in the array containing uint256 type variables
     // @param uint[] represents an array of unsigned integers
     function sum(uint[] memory self) internal pure returns(uint) {
        uint total;
        for (uint i = 0; i < self.length; i++) {
           total+=self[i];
        }
        return total;
      }
    
     // @dev This function returns true if an unsigned integer value exists in an array
     // @param uint[] represents an array of unsigned integers
     // @param _value represents an unsigned integer
     function contains(uint[] memory self, uint _value) internal pure returns(bool) {
        for (uint i = 0; i < self.length; i++) {
            if (self[i] == _value) return true;
        }
        return false;
     }
     // @dev This function returns true if an address exists in an array
     // @param address[] represents an array of addresses
     // @param _value represents an address
     function contains(address[] memory self, address _value) internal pure returns(bool) {
        for (uint i = 0; i < self.length; i++) {
            if (self[i] == _value) return true;
        }
        return false;
     }

     // @dev This function returns the index of an uint value
     // @param uint[] represents an array of unsigned integers
     // @param _value represents an unsigned integer
     function indexOf(uint[] memory self, uint _value) internal pure returns(uint) {
        for (uint i = 0; i < self.length; i++) {
            if (self[i] == _value) return i;
        }
        revert("Element not found in the array");
      }
      
    // @dev This function returns the index of an address value
    // @param address[] represents an array of addresses
    // @param _value represents an address
     function indexOf(address[] memory self, address _value) internal pure returns(uint) {
        for (uint i = 0; i < self.length; i++) {
            if (self[i] == _value) return i;
        }
        revert("Element not found in the array");
     }

    // @dev This function sorts an array using the insertion sort algorithm
    // @param uint[] represents an unsigned integer array 
    // @notice The insertion sort is most efficient with smaller input sizes but takes time twice the size of the input with larger data sets
    function insertionSort(uint[] storage _array) internal returns (uint[] storage) {
        uint start = 0;
        while (start < _array.length-1){
            uint smallest = _array[start];
            uint position = start;
            for (uint i = start+1; i<_array.length; i++){
                if (_array[i]<smallest){
                    smallest = _array[i]; 
                    position = i;
                }
            }
            _array[position] = _array[start]; _array[start] = smallest;
            start++;
        }
        return _array;
    }
}