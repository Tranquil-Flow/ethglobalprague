// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Test7702
 * @dev Contract to test EIP-7702 functionality for pulling tokens from a user's account
 */
contract Test7702 {
    address public owner;
    
    event TokensPulled(address indexed user, address indexed token, uint256 amount);
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    /**
     * @dev Pull tokens from a user's account
     * @param token Address of the token to pull
     * @param amount Amount of tokens to pull
     * 
     * Note: User must have authorized this contract using EIP-7702
     * and approved this contract to spend their tokens
     */
    function pullTokens(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        
        // Transfer tokens from the caller to this contract
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");
        
        emit TokensPulled(msg.sender, token, amount);
    }
}
