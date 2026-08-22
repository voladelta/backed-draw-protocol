// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IRandomnessAdapter } from "../../contracts/interfaces/IRandomnessAdapter.sol";

contract MockRandomnessAdapter is IRandomnessAdapter {
    uint256 public seed;
    uint256 public nonce;
    bool public requestsRevert;
    mapping(bytes32 requestId => bool pending) public pending;

    function setSeed(uint256 seed_) external {
        seed = seed_;
    }

    function setRequestsRevert(bool requestsRevert_) external {
        requestsRevert = requestsRevert_;
    }

    function requestRandomness(bytes32 commitment, uint32) external returns (bytes32 requestId) {
        require(!requestsRevert, "request failed");
        requestId = keccak256(abi.encode(msg.sender, commitment, ++nonce));
        pending[requestId] = true;
    }

    function verifyAndConsume(bytes32 requestId, bytes calldata) external returns (uint256[] memory words) {
        require(pending[requestId], "not pending");
        pending[requestId] = false;
        words = new uint256[](1);
        words[0] = seed;
    }

    function isRequestPending(bytes32 requestId) external view returns (bool) {
        return pending[requestId];
    }
}
