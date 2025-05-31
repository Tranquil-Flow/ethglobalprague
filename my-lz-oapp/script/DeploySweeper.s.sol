// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../contracts/ExternalSweeper.sol";
import "../contracts/OriginSweeper.sol";

contract DeploySweeperScript is Script {
    // CREATE2 requires a salt for deterministic addresses
    bytes32 constant SALT = bytes32(uint256(0x123456789));
    
    // Endpoint addresses for different chains
    address constant ENDPOINT_OPTIMISM = 0x1a44076050125825900e736c501f859c50fE728c;  // Optimism
    address constant ENDPOINT_BASE = 0x1a44076050125825900e736c501f859c50fE728c;      // Base
    address constant ENDPOINT_UNICHAIN = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;   // Unichain
    
    // Chain IDs for LayerZero
    uint32 constant CHAIN_ID_OPTIMISM = 111;   // Optimism
    uint32 constant CHAIN_ID_BASE = 184;       // Base
    uint32 constant CHAIN_ID_UNICHAIN = 130;     // Unichain
    
    // Factory contract that will use CREATE2 for deployment
    address factory;
    
    // TODO: change to be more flexible for specifying origin and external chains
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy CREATE2 Factory first (or use an existing one)
        factory = deployFactory();
        console.log("Factory deployed at:", factory);
        
        // Get the deployer address
        address deployer = vm.addr(deployerPrivateKey);
        
        // Determine current chain and deploy appropriate contracts
        address originSweeperAddr;
        address externalSweeperAddr;
        
        if (block.chainid == 10) { // Optimism
            console.log("Deploying on Optimism (Main Chain)");
            
            // Deploy OriginSweeper on Optimism (main chain)
            address finalReceiverAddress = deployer; // Use deployer as receiver
            uint totalChainsSelling = 3; // We're selling on 3 chains
            
            originSweeperAddr = deployOriginSweeper(
                ENDPOINT_OPTIMISM, 
                deployer, 
                finalReceiverAddress, 
                totalChainsSelling
            );
            
            console.log("OriginSweeper deployed on Optimism at:", originSweeperAddr);
            
            // Calculate the address where ExternalSweeper would be deployed on other chains
            bytes memory constructorArgsBase = abi.encode(
                ENDPOINT_BASE, 
                deployer, 
                originSweeperAddr, 
                CHAIN_ID_OPTIMISM
            );
            
            bytes memory bytecodeBase = abi.encodePacked(
                type(ExternalSweeper).creationCode, 
                constructorArgsBase
            );
            
            address externalSweeperOnBase = computeCreate2Address(SALT, bytecodeBase);
            
            bytes memory constructorArgsUnichain = abi.encode(
                ENDPOINT_UNICHAIN, 
                deployer, 
                originSweeperAddr, 
                CHAIN_ID_OPTIMISM
            );
            
            bytes memory bytecodeUnichain = abi.encodePacked(
                type(ExternalSweeper).creationCode, 
                constructorArgsUnichain
            );
            
            address externalSweeperOnUnichain = computeCreate2Address(SALT, bytecodeUnichain);
            
            console.log("ExternalSweeper address on Base will be:", externalSweeperOnBase);
            console.log("ExternalSweeper address on Unichain will be:", externalSweeperOnUnichain);
            
        } else if (block.chainid == 8453) { // Base
            console.log("Deploying on Base (External Chain)");
            
            // Calculate what the OriginSweeper address should be on Optimism
            address finalReceiverAddress = deployer;
            uint totalChainsSelling = 3;
            
            bytes memory constructorArgsOrigin = abi.encode(
                ENDPOINT_OPTIMISM, 
                deployer, 
                finalReceiverAddress, 
                totalChainsSelling
            );
            
            bytes memory bytecodeOrigin = abi.encodePacked(
                type(OriginSweeper).creationCode, 
                constructorArgsOrigin
            );
            
            originSweeperAddr = computeCreate2Address(SALT, bytecodeOrigin);
            console.log("OriginSweeper address on Optimism should be:", originSweeperAddr);
            
            // Deploy ExternalSweeper on Base
            externalSweeperAddr = deployExternalSweeper(
                ENDPOINT_BASE,
                deployer,
                originSweeperAddr,
                CHAIN_ID_OPTIMISM
            );
            
            console.log("ExternalSweeper deployed on Base at:", externalSweeperAddr);
            
        } else if (block.chainid == 130) { // Unichain
            console.log("Deploying on Unichain (External Chain)");
            
            // Calculate what the OriginSweeper address should be on Optimism
            address finalReceiverAddress = deployer;
            uint totalChainsSelling = 3;
            
            bytes memory constructorArgsOrigin = abi.encode(
                ENDPOINT_OPTIMISM, 
                deployer, 
                finalReceiverAddress, 
                totalChainsSelling
            );
            
            bytes memory bytecodeOrigin = abi.encodePacked(
                type(OriginSweeper).creationCode, 
                constructorArgsOrigin
            );
            
            originSweeperAddr = computeCreate2Address(SALT, bytecodeOrigin);
            console.log("OriginSweeper address on Optimism should be:", originSweeperAddr);
            
            // Deploy ExternalSweeper on Unichain
            externalSweeperAddr = deployExternalSweeper(
                ENDPOINT_UNICHAIN,
                deployer,
                originSweeperAddr,
                CHAIN_ID_OPTIMISM
            );
            
            console.log("ExternalSweeper deployed on Unichain at:", externalSweeperAddr);
            
        } else {
            revert("Unsupported chain");
        }
        
        vm.stopBroadcast();
    }
    
    // Compute the address where a contract will be deployed using CREATE2
    function computeCreate2Address(bytes32 salt, bytes memory bytecode) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            factory,
            salt,
            keccak256(bytecode)
        )))));
    }
    
    function deployFactory() internal returns (address) {
        // Simple CREATE2 factory contract - bytecode defined inline
        bytes memory factoryBytecode = hex"608060405234801561001057600080fd5b50610474806100206000396000f3fe608060405234801561001057600080fd5b50600436106100415760003560e01c8063485cc95514610046578063f4f3b50c14610062578063fa87aff014610087575b600080fd5b610060600480360381019061005b91906102c9565b6100a3565b005b61007c600480360381019061007791906102fb565b6100bb565b6040516100899190610363565b60405180910390f35b6100a160048036038101906100a69190610385565b61018f565b005b8173ffffffffffffffffffffffffffffffffffffffff16610100826100bb565b73ffffffffffffffffffffffffffffffffffffffff16146100af57fe5b5050565b6000818360405160200161010792919061042d565b604051602081830303815290604052805190602001209050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff161115610187576040517f08c379a000000000000000000000000000000000000000000000000000000000815260040161017e906103d7565b60405180910390fd5b92915050565b60008282604051610221907f608060405234801561001057600080fd5b5060405161021e38038061021e833981810160405281019061003491906100bd565b8073ffffffffffffffffffffffffffffffffffffffff1660808173ffffffffffffffffffffffffffffffffffffffff1660601b815250505060c6565b60405181818190604052826000823e818015610247578181f35b505050565b6040516020016101cd9190610363565b604051602081830303815290604052805190602001209050600060405180602001604052806000815250905060008373ffffffffffffffffffffffffffffffffffffffff1683604051610218919061037e565b6000604051808303816000865af19150503d806000811461026c576040519150601f19603f3d011682016040523d82523d6000602084013e610271565b606091505b50509050600073ffffffffffffffffffffffffffffffffffffffff16816020015173ffffffffffffffffffffffffffffffffffffffff16146102af57fe5b50505050565b6000813590506102c38161045a565b92915050565b600080604083850312156102dc57600080fd5b60006102ea858286016102b4565b92505060206102fb858286016102b4565b9150509250929050565b60006020828403121561030d57600080fd5b600061031b848285016102b4565b91505092915050565b61032d8161037e565b82525050565b600061033e82610407565b6103488185610412565b9350610358818560208601610427565b80840191505092915050565b60006020820190506103786000830184610324565b92915050565b600061038d8284610333565b915081905092915050565b6000604051905090565b600080fd5b6000601f19601f8301169050919050565b600061042a826103f6565b9050919050565b600061043c8285610333565b91506104478361041d565b915081905092915050565b6104638161041f565b811461046e57600080fd5b50565b90565b6000611f8082840312156104a857600080fd5b602082019050919050565b6000602082840312156104c657600080fd5b600082013590506104d7816104eb565b92915050565b600081359050610497816104eb565b6104f48161041f565b81146104ff57600080fd5b50565b60008135905061051181610507565b92915050565b60006104e1828461050256";
        
        // Deploy factory using regular CREATE
        assembly {
            let deployed := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
            if iszero(deployed) { revert(0, 0) }
            sstore(factory.slot, deployed)
        }
        
        return factory;
    }
    
    function deployOriginSweeper(
        address endpoint,
        address delegate,
        address finalReceiverAddress,
        uint totalChainsSelling
    ) internal returns (address) {
        // Generate creation bytecode with constructor arguments
        bytes memory constructorArgs = abi.encode(endpoint, delegate, finalReceiverAddress, totalChainsSelling);
        bytes memory bytecode = abi.encodePacked(type(OriginSweeper).creationCode, constructorArgs);
        
        // Deploy using factory's CREATE2
        bytes memory deployData = abi.encodeWithSignature("deploy(bytes32,bytes)", SALT, bytecode);
        (bool success, bytes memory returnData) = factory.call(deployData);
        require(success, "Failed to deploy OriginSweeper");
        
        return abi.decode(returnData, (address));
    }
    
    function deployExternalSweeper(
        address endpoint,
        address delegate,
        address mainContract,
        uint32 mainChainId
    ) internal returns (address) {
        // Generate creation bytecode with constructor arguments
        bytes memory constructorArgs = abi.encode(endpoint, delegate, mainContract, mainChainId);
        bytes memory bytecode = abi.encodePacked(type(ExternalSweeper).creationCode, constructorArgs);
        
        // Deploy using factory's CREATE2
        bytes memory deployData = abi.encodeWithSignature("deploy(bytes32,bytes)", SALT, bytecode);
        (bool success, bytes memory returnData) = factory.call(deployData);
        require(success, "Failed to deploy ExternalSweeper");
        
        return abi.decode(returnData, (address));
    }
}

contract CREATE2Factory {
    event Deployed(address addr, bytes32 salt);
    
    // Computes the address where a contract will be deployed using CREATE2
    function computeAddress(bytes32 salt, bytes memory bytecode) public view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(bytecode)
        )))));
    }
    
    // Deploys a contract using CREATE2
    function deploy(bytes32 salt, bytes memory bytecode) public returns (address) {
        address addr;
        
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
        
        emit Deployed(addr, salt);
        return addr;
    }
} 