// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { WebAuthnLib } from "./utils/WebAuthnLib.sol";
import { ERC7579ValidatorBase } from "modulekit/Modules.sol";
import { UserOperation, UserOperationLib } from "modulekit/external/ERC4337.sol";
import { EncodedModuleTypes, ModuleTypeLib, ModuleType } from "erc7579/lib/ModuleTypeLib.sol";

struct PassKeyId {
    uint256 pubKeyX;
    uint256 pubKeyY;
    string keyId;
}

contract WebAuthnValidator is ERC7579ValidatorBase {
    using UserOperationLib for UserOperation;

    error NoPassKeyRegisteredForSmartAccount(address smartAccount);
    error AlreadyInitedForSmartAccount(address smartAccount);

    event NewPassKeyRegistered(address indexed smartAccount, string keyId);

    mapping(address account => PassKeyId passkeyConfig) public smartAccountPassKeys;

    function onInstall(bytes calldata data) external override {
        PassKeyId memory passkey = abi.decode(data, (PassKeyId));
        smartAccountPassKeys[msg.sender] = passkey;
    }

    function onUninstall(bytes calldata) external override {
        _removePassKey();
    }

    function getAuthorizedKey(address account) public view returns (PassKeyId memory passkey) {
        passkey = smartAccountPassKeys[account];
    }

    function _removePassKey() internal {
        smartAccountPassKeys[msg.sender] = PassKeyId(0, 0, "");
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    )
        external
        override
        returns (ValidationData)
    {
        (
            ,
            bytes memory authenticatorData,
            bytes1 authenticatorDataFlagMask,
            bytes memory clientData,
            uint256 clientChallengeDataOffset,
            uint256[2] memory rs
        ) = abi.decode(userOp.signature, (bytes32, bytes, bytes1, bytes, uint256, uint256[2]));

        PassKeyId memory passKey = smartAccountPassKeys[userOp.getSender()];
        require(passKey.pubKeyY != 0 && passKey.pubKeyY != 0, "Key not found");
        uint256[2] memory Q = [passKey.pubKeyX, passKey.pubKeyY];
        bool isValidSignature = WebAuthnLib.checkSignature(
            authenticatorData,
            authenticatorDataFlagMask,
            clientData,
            userOpHash,
            clientChallengeDataOffset,
            rs,
            Q
        );

        return _packValidationData(!isValidSignature, 0, type(uint48).max);
    }

    function isValidSignatureWithSender(
        address,
        bytes32,
        bytes calldata
    )
        external
        view
        virtual
        override
        returns (bytes4)
    {
        return EIP1271_FAILED;
    }

    function name() external pure returns (string memory) {
        return "WebAuthnValidator";
    }

    function version() external pure returns (string memory) {
        return "0.0.1";
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_VALIDATOR;
    }

    function getModuleTypes() external view returns (EncodedModuleTypes) { }

    function isInitialized(address smartAccount) external view returns (bool) { }
}
