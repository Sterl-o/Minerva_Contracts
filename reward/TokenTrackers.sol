// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./RewardTracker.sol";

contract StakedMineTracker is RewardTracker {
    constructor() public RewardTracker("Staked MINE", "sMINE") {}
}

contract BonusMineTracker is RewardTracker {
    constructor() public RewardTracker("Staked + Bonus MINE", "sbMINE") {}
}

contract FeeMineTracker is RewardTracker {
    constructor() public RewardTracker("Staked + Bonus + Fee MINE", "sbfMINE") {}
}

contract StakedMlpTracker is RewardTracker {
    constructor() public RewardTracker("Fee + Staked MLP", "fsMLP") {}
}

contract FeeMlpTracker is RewardTracker {
    constructor() public RewardTracker("Fee MLP", "fMLP") {}
}
