// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "modulekit/ModuleKit.sol";
import "modulekit/Modules.sol";
import "modulekit/Helpers.sol";
import "src/MultiECDSAWithExpirationValidator.sol";
import "frame-verifier/Encoder.sol";

contract MultiECDSAWithExpirationValidatorTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;
    using ModuleKitUserOp for *;

    // main account and dependencies
    RhinestoneAccount internal instance;
    MultiECDSAWithExpirationValidator internal validator;

    Account owner;

    function setUp() public {
        init();

        validator = new MultiECDSAWithExpirationValidator();
        vm.label(address(validator), "MultiECDSAWithExpirationValidatorTest");

        instance = makeRhinestoneAccount("MultiECDSA");
        vm.deal(address(instance.account), 10 ether);

        owner = makeAccount("owner");
    }

    function signHash(uint256 privKey, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, ECDSA.toEthSignedMessageHash(digest));
        return abi.encodePacked(r, s, v);
    }

    function testExec__Send() public {
        instance.installValidator(address(validator), abi.encode(type(uint48).max, owner.addr));
        address target = makeAddr("target");
        uint256 value = 1 ether;
        uint256 prevBalance = target.balance;

        UserOpData memory userOpData = instance.getExecOps({
            target: target,
            value: value,
            callData: "",
            txValidator: address(validator)
        });
        bytes memory signature = signHash(owner.key, userOpData.userOpHash);
        userOpData.userOp.signature = abi.encode(0, signature);
        userOpData.execUserOps();

        assertEq(target.balance, prevBalance + value);
    }

    function testExec__Send__RevertWhen__Expired() public {
        instance.installValidator(address(validator), abi.encode(1, owner.addr));
        address target = makeAddr("target");
        uint256 value = 1 ether;
        uint256 prevBalance = target.balance;

        UserOpData memory userOpData = instance.getExecOps({
            target: target,
            value: value,
            callData: "",
            txValidator: address(validator)
        });
        bytes memory signature = signHash(owner.key, userOpData.userOpHash);
        userOpData.userOp.signature = abi.encode(0, signature);
        userOpData.execUserOps();

        assertEq(target.balance, prevBalance + value);

        vm.warp(2);

        UserOpData memory userOpData2 = instance.getExecOps({
            target: target,
            value: value,
            callData: "",
            txValidator: address(validator)
        });
        bytes memory signature2 = signHash(owner.key, userOpData2.userOpHash);
        userOpData2.userOp.signature = abi.encode(0, signature2);

        vm.expectRevert();
        userOpData2.execUserOps();
    }
}
