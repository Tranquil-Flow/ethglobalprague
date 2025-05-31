// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Test7702.sol";

/**
 * @title Test7702Factory
 * @dev Factory contract to deploy Test7702 using CREATE2 for consistent addresses across chains
 */
contract Test7702Factory {
    address public implementation;
    bytes32 public constant SALT = keccak256("EIP7702_TEST_CONTRACT_SALT");
    
    event Deployed(address indexed implementation, address indexed deployedAt);
    
    /**
     * @dev Deploys a new Test7702 contract using CREATE2
     * @return The address of the deployed contract
     */
    function deploy() external returns (address) {
        // Create deployment bytecode
        bytes memory bytecode = type(Test7702).creationCode;
        
        // Deploy with CREATE2
        address deployedAddress;
        bytes32 salt = SALT;
        assembly {
            deployedAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(deployedAddress)) {
                revert(0, 0)
            }
        }
        
        implementation = deployedAddress;
        emit Deployed(implementation, deployedAddress);
        
        return deployedAddress;
    }
    
    /**
     * @dev Computes the address where the contract will be deployed
     * @return The address where the contract will be deployed
     */
    function computeAddress() external view returns (address) {
        bytes memory bytecode = type(Test7702).creationCode;
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                SALT,
                keccak256(bytecode)
            )
        );
        
        return address(uint160(uint256(hash)));
    }
} 