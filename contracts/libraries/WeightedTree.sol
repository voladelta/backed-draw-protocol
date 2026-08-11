// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library WeightedTree {
    using SafeCast for uint256;

    error InvalidCapacity();
    error InvalidSlot(uint256 slot);
    error TargetOutOfBounds(uint256 target, uint256 totalWeight);

    struct Tree {
        uint32 capacity;
        mapping(uint256 node => uint256 weight) nodes;
        mapping(uint256 node => bytes32 hash) hashes;
        mapping(uint32 slot => uint256 weight) leafWeights;
    }

    function initialize(Tree storage self, uint32 requestedCapacity) internal {
        if (self.capacity != 0 || requestedCapacity == 0 || requestedCapacity > 1 << 31) {
            revert InvalidCapacity();
        }
        uint32 capacity = 1;
        while (capacity < requestedCapacity) capacity <<= 1;
        self.capacity = capacity;
    }

    function set(Tree storage self, uint32 slot, uint256 newWeight, bytes32 leafCommitment) internal {
        if (slot >= self.capacity) revert InvalidSlot(slot);
        uint256 oldWeight = self.leafWeights[slot];
        self.leafWeights[slot] = newWeight;
        uint256 node = uint256(self.capacity) + slot;
        while (node != 0) {
            if (newWeight >= oldWeight) self.nodes[node] += newWeight - oldWeight;
            else self.nodes[node] -= oldWeight - newWeight;
            node >>= 1;
        }

        node = uint256(self.capacity) + slot;
        self.hashes[node] = newWeight == 0 ? bytes32(0) : leafCommitment;
        node >>= 1;
        while (node != 0) {
            uint256 left = node << 1;
            uint256 right = left | 1;
            self.hashes[node] = keccak256(
                abi.encode(self.nodes[left], self.hashes[left], self.nodes[right], self.hashes[right])
            );
            node >>= 1;
        }
    }

    function total(Tree storage self) internal view returns (uint256) {
        return self.nodes[1];
    }

    function root(Tree storage self) internal view returns (bytes32) {
        return self.hashes[1];
    }

    function weightAt(Tree storage self, uint32 slot) internal view returns (uint256) {
        return self.leafWeights[slot];
    }

    function find(Tree storage self, uint256 target) internal view returns (uint32 slot) {
        uint256 totalWeight = total(self);
        if (target >= totalWeight) revert TargetOutOfBounds(target, totalWeight);
        uint256 node = 1;
        while (node < self.capacity) {
            uint256 left = node << 1;
            uint256 leftWeight = self.nodes[left];
            if (target < leftWeight) {
                node = left;
            } else {
                target -= leftWeight;
                node = left | 1;
            }
        }
        slot = (node - self.capacity).toUint32();
    }
}
