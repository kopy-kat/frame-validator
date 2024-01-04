// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { ERC7579ValidatorBase, ERC7579HookBase } from "modulekit/Modules.sol";
import { UserOperation } from "modulekit/ModuleKit.sol";
import { SignatureCheckerLib } from "solady/src/utils/SignatureCheckerLib.sol";

contract DeadmanSwitch is ERC7579HookBase, ERC7579ValidatorBase {
    using SignatureCheckerLib for address;

    struct DeadmanSwitchStorage {
        uint48 lastAccess;
        uint48 timeout;
        address nominee;
    }

    mapping(address account => DeadmanSwitchStorage config) private _lastAccess;

    event Recovery(address account, address nominee);

    error MissingCondition();

    function onInstall(bytes calldata data) external {
        (address nominee, uint48 timeout) = abi.decode(data, (address, uint48));
        DeadmanSwitchStorage storage config = _lastAccess[msg.sender];

        config.lastAccess = uint48(block.timestamp);
        config.timeout = timeout;
        config.nominee = nominee;
    }

    function onUninstall(bytes calldata) external override {
        delete _lastAccess[msg.sender];
    }

    function name() external pure override returns (string memory) {
        return "DeadmanSwitch";
    }

    function version() external pure override returns (string memory) {
        return "0.0.1";
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_HOOK;
    }

    function preCheck(address, bytes calldata) external returns (bytes memory) {
        DeadmanSwitchStorage storage config = _lastAccess[msg.sender];
        config.lastAccess = uint48(block.timestamp);
    }

    function postCheck(bytes calldata) external pure returns (bool success) {
        success = true;
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    )
        external
        override
        returns (ValidationData)
    {
        DeadmanSwitchStorage memory config = _lastAccess[userOp.sender];
        if (config.nominee == address(0)) return VALIDATION_FAILED;
        bool isValid = config.nominee.isValidSignatureNow(userOpHash, userOp.signature);
        return _packValidationData({
            sigFailed: !isValid,
            validUntil: config.lastAccess + config.timeout,
            validAfter: type(uint48).max
        });
    }

    function isValidSignatureWithSender(
        address,
        bytes32,
        bytes calldata
    )
        external
        pure
        override
        returns (bytes4)
    {
        return EIP1271_FAILED;
    }
}
