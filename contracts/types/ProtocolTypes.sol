// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library ProtocolTypes {
    enum PositionStatus {
        Staged,
        Active,
        BackingChangeQueued,
        WithdrawalQueued,
        Selected,
        Settling,
        Closed,
        Withdrawn,
        WithdrawalClaimable
    }

    enum EpochStatus {
        Idle,
        Collecting,
        RandomnessRequested,
        RandomnessReady,
        Resolving,
        Finalized,
        Cancelled,
        Finalizing,
        Cancelling,
        Refunding
    }

    enum PullStatus {
        Pending,
        Revealed,
        Settled
    }

    enum SettlementChoice {
        Keep,
        Cash,
        Draw,
        Relist
    }

    struct MarketConfig {
        uint256 marketId;
        bytes32 collectionSetId;
        address settlementAsset;
        address protocolRegistry;
        address governor;
        address guardian;
        address treasury;
        address insuranceReserve;
        address buybackReceiver;
        address randomnessAdapter;
        address eligibilityPolicy;
        address referralRegistry;
        address rewardController;
        address trustedRouter;
        uint128 minBacking;
        uint128 maxBacking;
        uint32 maxActivePositions;
        uint32 maxDrawsPerEpoch;
        uint32 collectionWindow;
        uint32 randomnessTimeout;
        uint32 decisionWindow;
        uint16 markupBps;
        uint16 cashPayoutBps;
        uint16 keepPayoutBps;
    }

    function isValidEconomicPolicy(uint16 markupBps, uint16 cashPayoutBps, uint16 keepPayoutBps)
        internal
        pure
        returns (bool)
    {
        return markupBps <= 5_000 && cashPayoutBps >= 8_000 && cashPayoutBps <= 9_500
            && keepPayoutBps >= 9_500 && keepPayoutBps <= 10_000 && cashPayoutBps <= keepPayoutBps;
    }

    struct Position {
        address collection;
        uint256 tokenId;
        uint128 backing;
        uint128 pendingBacking;
        uint32 treeSlot;
        PositionStatus status;
        address earningsRecipient;
        uint256 baseDebt;
        uint256 markupDebt;
        uint256 rewardDebt;
        uint256 selectedCashEarnings;
        uint256 selectedRewardInput;
    }

    struct PullOrderInput {
        address receiver;
        uint32 drawCount;
        uint128 maxUnitPrice;
        uint128 maxTotalPrice;
        uint48 deadline;
        bytes32 referralCode;
    }

    struct PullOrder {
        address buyer;
        address receiver;
        uint32 drawCount;
        uint32 resolvedCount;
        uint128 maxUnitPrice;
        uint128 escrowRemaining;
        uint48 deadline;
        bytes32 referralCode;
        address referrer;
    }

    struct PullReceiptData {
        uint256 marketId;
        uint256 epochId;
        uint256 positionId;
        address originalBuyer;
        address receiver;
        uint128 chargedPrice;
        uint128 selectedBacking;
        uint48 revealedAt;
        uint48 decisionDeadline;
        PullStatus status;
    }
}
