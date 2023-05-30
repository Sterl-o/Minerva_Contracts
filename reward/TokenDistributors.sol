// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./RewardDistributor.sol";
import "./BonusDistributor.sol";

contract StakedMineDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}

contract BonusMineDistributor is BonusDistributor {
    constructor(address _rewardToken, address _rewardTracker) public BonusDistributor(_rewardToken, _rewardTracker) {}
}

contract FeeMineDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}

contract StakedMlpDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}

contract FeeMlpDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}
