// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Vester.sol";

contract MineVester is Vester {
    constructor(
        uint256 _vestingDuration,
        address _esToken,
        address _pairToken,
        address _claimableToken,
        address _rewardTracker
    ) public Vester("Vested MINE", "vMINE", _vestingDuration, _esToken, _pairToken, _claimableToken, _rewardTracker) {}
}
