// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { IERC721 } from "forge-std/interfaces/IERC721.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { ERC7579HookDestruct } from "modulekit/modules/ERC7579HookDestruct.sol";
import { IERC7579Execution } from "modulekit/Accounts.sol";

contract ColdStorageHook is ERC7579HookDestruct {
    error UnsupportedExecution();
    error UnauthorizedAccess();

    using EnumerableMap for EnumerableMap.Bytes32ToBytes32Map;

    bytes32 internal constant PASS = keccak256("pass");

    struct VaultConfig {
        uint128 waitPeriod;
        address owner;
    }

    mapping(address subAccount => VaultConfig) internal vaultConfig;
    mapping(address subAccount => EnumerableMap.Bytes32ToBytes32Map) internal executions;

    event ExecutionRequested(
        address indexed subAccount,
        address target,
        uint256 value,
        bytes callData,
        uint256 executeAfter
    );

    event ExecutionExecuted(
        address indexed subAccount, address target, uint256 value, bytes callData
    );

    function _getTokenTxReceiver(bytes calldata callData)
        internal
        pure
        returns (address receiver)
    {
        bytes4 functionSig = bytes4(callData[0:4]);
        bytes calldata params = callData[4:];
        if (functionSig == IERC20.transfer.selector) {
            (receiver,) = abi.decode(params, (address, uint256));
        } else if (functionSig == IERC20.transferFrom.selector) {
            (, receiver,) = abi.decode(params, (address, address, uint256));
        } else if (functionSig == IERC721.transferFrom.selector) {
            (, receiver,) = abi.decode(params, (address, address, uint256));
        }
    }

    /**
     * Function that must be triggered from subaccount.
     * requests an execution to happen in the future
     */
    function requestTimelockedExecution(
        IERC7579Execution.Execution calldata _exec,
        uint256 additionalWait
    )
        external
    {
        VaultConfig memory _config = vaultConfig[msg.sender];
        bytes32 executionHash = _execDigest(_exec.target, _exec.value, _exec.callData);

        if (_exec.callData.length != 0) {
            // check that transaction is only a token transfer
            address tokenReceiver = _getTokenTxReceiver(_exec.callData);
            if (tokenReceiver != _config.owner) {
                // Else check that transaction is to setWaitPeriod
                if (bytes4(_exec.callData[0:4]) != this.setWaitPeriod.selector) {
                    revert("Invalid receiver transfer");
                }
            }
        }

        uint256 executeAfter = uint256(block.timestamp + _config.waitPeriod + additionalWait);
        bytes32 entry = bytes32(executeAfter);

        // write executionHash to storage
        executions[msg.sender].set(executionHash, entry);

        emit ExecutionRequested(msg.sender, _exec.target, _exec.value, _exec.callData, executeAfter);
    }

    function setWaitPeriod(uint256 waitPeriod) external {
        if (waitPeriod == 0) {
            revert("Wait period cannot be 0");
        }
        vaultConfig[msg.sender].waitPeriod = uint128(waitPeriod);
    }

    function _execDigest(
        address to,
        uint256 value,
        bytes calldata callData
    )
        internal
        pure
        returns (bytes32)
    {
        bytes memory _callData = callData;
        return _execDigestMemory(to, value, _callData);
    }

    function _execDigestMemory(
        address to,
        uint256 value,
        bytes memory callData
    )
        internal
        pure
        returns (bytes32 digest)
    {
        digest = keccak256(abi.encodePacked(to, value, callData));
    }

    function onInstall(bytes calldata data) external override {
        VaultConfig storage _config = vaultConfig[msg.sender];
        (_config.waitPeriod, _config.owner) = abi.decode(data, (uint128, address));
    }

    function onUninstall(bytes calldata data) external override {
        delete vaultConfig[msg.sender].waitPeriod;
        delete vaultConfig[msg.sender].owner;
    }

    function onPostCheck(bytes calldata hookData)
        internal
        virtual
        override
        returns (bool success)
    {
        if (
            keccak256(hookData) == keccak256(abi.encode(this.requestTimelockedExecution.selector))
                || keccak256(hookData) == keccak256(abi.encode(PASS))
        ) {
            return true;
        }

        return false;
    }

    function onExecute(
        address msgSender,
        address target,
        uint256 value,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        bytes4 functionSig = bytes4(callData[0:4]);

        // check if call is a requestTimelockedExecution
        if (target == address(this) && functionSig == this.requestTimelockedExecution.selector) {
            return abi.encode(this.requestTimelockedExecution.selector);
        } else {
            bytes32 executionHash = _execDigestMemory(target, value, callData);
            (bool success, bytes32 entry) = executions[msg.sender].tryGet(executionHash);

            if (!success) revert UnauthorizedAccess();

            uint256 requestTimeStamp = uint256(entry);
            if (requestTimeStamp > block.timestamp) revert UnauthorizedAccess();

            emit ExecutionExecuted(msg.sender, target, value, callData);

            return abi.encode(PASS);
        }
    }

    function onExecuteBatch(
        address msgSender,
        IERC7579Execution.Execution[] calldata
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onExecuteFromExecutor(
        address msgSender,
        address target,
        uint256 value,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onExecuteBatchFromExecutor(
        address msgSender,
        IERC7579Execution.Execution[] calldata
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onInstallExecutor(
        address msgSender,
        address executor,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onUninstallExecutor(
        address msgSender,
        address executor,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onInstallValidator(
        address msgSender,
        address validator,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onUninstallValidator(
        address msgSender,
        address validator,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onUninstallHook(
        address msgSender,
        address hookModule,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onInstallHook(
        address msgSender,
        address hookModule,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function version() external pure virtual override returns (string memory) {
        return "1.0.0";
    }

    function name() external pure virtual override returns (string memory) {
        return "ColdStorageHook";
    }

    function isModuleType(uint256 isType) external pure virtual override returns (bool) {
        return isType == TYPE_HOOK;
    }
}
