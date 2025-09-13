// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Hooks} from "v4-core/libraries/Hooks.sol";

/// @notice Library for mining hook addresses
library HookMiner {
    // seed for create2 address mining
    uint256 constant SEED = 0x4444;

    /// @notice Find a salt that produces a hook address with the desired flags
    /// @param deployer The address that will deploy the hook
    /// @param flags The desired flags for the hook address
    /// @param creationCode The creation code of the hook contract
    /// @param constructorArgs The encoded constructor arguments
    /// @return hookAddress The address the hook will have
    /// @return salt The salt to use with create2
    function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs)
        internal
        pure
        returns (address hookAddress, bytes32 salt)
    {
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        for (uint256 i = 0; i < 100_000; i++) {
            salt = keccak256(abi.encodePacked(SEED, i));
            hookAddress = computeAddress(deployer, salt, creationCodeWithArgs);

            if (uint160(hookAddress) & uint160(0x00FF) == flags) {
                return (hookAddress, salt);
            }
        }

        revert("HookMiner: could not find salt");
    }

    /// @notice Compute the address of a contract deployed with create2
    function computeAddress(address deployer, bytes32 salt, bytes memory creationCode)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(creationCode)))))
        );
    }
}
