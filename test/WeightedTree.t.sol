// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { WeightedTree } from "../contracts/libraries/WeightedTree.sol";

contract WeightedTreeHarness {
    using WeightedTree for WeightedTree.Tree;
    WeightedTree.Tree private _tree;

    constructor(uint32 capacity) {
        _tree.initialize(capacity);
    }

    function set(uint32 slot, uint256 weight) external {
        _tree.set(slot, weight, keccak256(abi.encode(slot, weight)));
    }

    function find(uint256 target) external view returns (uint32) {
        return _tree.find(target);
    }

    function total() external view returns (uint256) {
        return _tree.total();
    }
}

contract WeightedTreeTest is Test {
    WeightedTreeHarness internal tree;

    function setUp() external {
        tree = new WeightedTreeHarness(5);
        tree.set(0, 10);
        tree.set(1, 20);
        tree.set(2, 30);
    }

    function testFindsCumulativeRanges() external view {
        assertEq(tree.find(0), 0);
        assertEq(tree.find(9), 0);
        assertEq(tree.find(10), 1);
        assertEq(tree.find(29), 1);
        assertEq(tree.find(30), 2);
        assertEq(tree.find(59), 2);
    }

    function testUpdateAndRemovePreserveTotal() external {
        tree.set(1, 5);
        assertEq(tree.total(), 45);
        tree.set(0, 0);
        assertEq(tree.total(), 35);
        assertEq(tree.find(0), 1);
        assertEq(tree.find(5), 2);
    }
}
