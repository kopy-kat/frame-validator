// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IFallbackMethod } from "modulekit/core/ExtensibleFallbackHandler.sol";

import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import "./interfaces/Flashloan.sol";
import { EncodedModuleTypes, ModuleTypeLib, ModuleType } from "erc7579/lib/ModuleTypeLib.sol";

contract FlashloanCallback is IFallbackMethod, ERC7579ExecutorBase {
    address immutable FALLBACK_HANDLER;

    mapping(address account => uint256) public nonce;

    constructor(address fallbackHandler) {
        FALLBACK_HANDLER = fallbackHandler;
    }

    function handle(
        address borrower,
        address sender,
        uint256 value,
        bytes calldata data
    )
        external
        override
        returns (bytes memory result)
    {
        if (data.length < 4) revert();
        if (msg.sender != FALLBACK_HANDLER) revert();

        bytes4 selector = bytes4(data[0:4]);

        if (selector == IERC3156FlashBorrower.onFlashLoan.selector) {
            (
                address lender,
                address token,
                uint256 value,
                uint256 fee,
                bytes memory tokenGatedAction
            ) = abi.decode(data[4:], (address, address, uint256, uint256, bytes));
            _onFlashloan(borrower, lender, token, value, fee, tokenGatedAction);
            return abi.encode(keccak256("ERC3156FlashBorrower.onFlashLoan"));
        }
    }

    function _onFlashloan(
        address borrower,
        address lender,
        address token,
        uint256 value,
        uint256 fee,
        bytes memory tokenGatedAction
    )
        internal
    {
        (FlashLoanType flashLoanType, bytes memory signature, bytes memory callData) =
            abi.decode(tokenGatedAction, (FlashLoanType, bytes, bytes));
        bytes32 hash = getTokengatedTxHash(callData, nonce[borrower]);
        // TODO signature
        (bool success,) = borrower.call(callData);
        if (!success) revert();
        nonce[borrower]++;
    }

    function getTokengatedTxHash(
        bytes memory transaction,
        uint256 _nonce
    )
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(transaction, _nonce));
    }

    function onInstall(bytes calldata data) external override { }

    function onUninstall(bytes calldata data) external override { }

    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }

    function name() external pure virtual returns (string memory) {
        return "FlashloanCallback";
    }

    function isModuleType(uint256 isType) external pure virtual override returns (bool) {
        return isType == TYPE_EXECUTOR;
    }

    function getModuleTypes() external view returns (EncodedModuleTypes) { }

    function isInitialized(address smartAccount) external view returns (bool) { }
}
