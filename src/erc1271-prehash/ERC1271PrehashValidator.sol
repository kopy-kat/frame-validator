// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { ERC7579ValidatorBase, UserOperation } from "modulekit/modules/ERC7579ValidatorBase.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { EncodedModuleTypes, ModuleTypeLib, ModuleType } from "erc7579/lib/ModuleTypeLib.sol";

contract ERC1271PrehashValidator is ERC7579ValidatorBase {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    mapping(address account => EnumerableSet.Bytes32Set) internal _validHashes;

    function addHash(bytes32 _hash) external {
        _validHashes[msg.sender].add(_hash);
    }

    function removeHash(bytes32 _hash) external {
        _validHashes[msg.sender].remove(_hash);
    }

    function isHash(address account, bytes32 _hash) public view returns (bool) {
        return _validHashes[account].contains(_hash);
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    )
        external
        virtual
        override
        returns (ValidationData)
    {
        return VALIDATION_FAILED;
    }

    function isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata data
    )
        external
        view
        virtual
        override
        returns (bytes4)
    {
        if (keccak256(data) != hash) return EIP1271_FAILED;
        if (isHash(sender, hash)) {
            return EIP1271_SUCCESS;
        } else {
            return EIP1271_FAILED;
        }
    }

    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }

    function name() external pure virtual returns (string memory) {
        return "ERC1271PrehashValidator";
    }

    function isModuleType(uint256 isType) external pure virtual override returns (bool) {
        return isType == TYPE_VALIDATOR;
    }

    function getModuleTypes() external view returns (EncodedModuleTypes) { }

    function isInitialized(address smartAccount) external view returns (bool) { }

    function onInstall(bytes calldata data) external override {
        if (data.length == 0) return;

        bytes32[] memory hashes = abi.decode(data, (bytes32[]));
        for (uint256 i; i < hashes.length; i++) {
            _validHashes[msg.sender].add(hashes[i]);
        }
    }

    function onUninstall(bytes calldata data) external override { }
}
