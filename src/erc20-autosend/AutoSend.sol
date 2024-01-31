// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "modulekit/core/sessionKey/ISessionValidationModule.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC7579Account } from "modulekit/Accounts.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { ModeLib } from "umsa/lib/ModeLib.sol";
import { ExecutionLib } from "umsa/lib/ExecutionLib.sol";
import { EncodedModuleTypes, ModuleTypeLib, ModuleType } from "umsa/lib/ModuleTypeLib.sol";

contract AutoSendSessionKey is ERC7579ExecutorBase, ISessionValidationModule {
    struct ExecutorAccess {
        address sessionKeySigner;
        address token;
        address receiver;
    }

    struct SpentLog {
        uint128 spent;
        uint128 maxAmount;
    }

    struct Params {
        address token;
        address receiver;
        uint128 amount;
    }

    error InvalidMethod(bytes4);
    error InvalidValue();
    error InvalidAmount();
    error InvalidTarget();
    error InvalidRecipient();

    mapping(address account => mapping(address token => SpentLog)) internal _log;

    function encode(ExecutorAccess memory transaction) public pure returns (bytes memory) {
        return abi.encode(transaction);
    }

    function getSpentLog(address account, address token) public view returns (SpentLog memory) {
        return _log[account][token];
    }

    function autoSend(Params calldata params) external {
        IERC7579Account smartAccount = IERC7579Account(msg.sender);

        SpentLog storage log = _log[msg.sender][params.token];

        uint128 newSpent = log.spent + params.amount;
        if (newSpent > log.maxAmount) {
            revert InvalidAmount();
        }
        log.spent = newSpent;

        smartAccount.executeFromExecutor(
            ModeLib.encodeSimpleSingle(),
            ExecutionLib.encodeSingle(
                params.token, 0, abi.encodeCall(IERC20.transfer, (params.receiver, params.amount))
            )
        );
    }

    function validateSessionParams(
        address destinationContract,
        uint256 callValue,
        bytes calldata callData,
        bytes calldata _sessionKeyData,
        bytes calldata /*_callSpecificData*/
    )
        public
        virtual
        override
        returns (address)
    {
        ExecutorAccess memory access = abi.decode(_sessionKeyData, (ExecutorAccess));

        bytes4 targetSelector = bytes4(callData[:4]);
        Params memory params = abi.decode(callData[4:], (Params));
        if (targetSelector != this.autoSend.selector) {
            revert InvalidMethod(targetSelector);
        }

        if (params.receiver != access.receiver) {
            revert InvalidRecipient();
        }

        if (destinationContract != address(this)) {
            revert InvalidTarget();
        }

        if (params.token != access.token) {
            revert InvalidTarget();
        }

        if (callValue != 0) {
            revert InvalidValue();
        }

        return access.sessionKeySigner;
    }

    function onInstall(bytes calldata data) external override {
        (address[] memory tokens, SpentLog[] memory log) = abi.decode(data, (address[], SpentLog[]));

        for (uint256 i; i < tokens.length; i++) {
            _log[msg.sender][tokens[i]] = log[i];
        }
    }

    function onUninstall(bytes calldata data) external override { }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }

    function getModuleTypes() external view returns (EncodedModuleTypes) { }

    function isInitialized(address smartAccount) external view returns (bool) { }

    function name() external pure virtual returns (string memory) {
        return "AutoSend";
    }

    function version() external pure virtual returns (string memory) {
        return "0.0.1";
    }
}
