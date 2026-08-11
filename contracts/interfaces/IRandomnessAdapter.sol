// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRandomnessAdapter {
    function requestRandomness(bytes32 commitment, uint32 wordCount) external returns (bytes32 requestId);
    function verifyAndConsume(bytes32 requestId, bytes calldata proof)
        external
        returns (uint256[] memory words);
    function isRequestPending(bytes32 requestId) external view returns (bool);
}
