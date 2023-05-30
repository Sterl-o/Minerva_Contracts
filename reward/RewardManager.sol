// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../access/Governable.sol";
import "../peripherals/interfaces/ITimelock.sol";

contract RewardManager is Governable {
    bool public isInitialized;

    ITimelock public timelock;
    address public rewardRouter;

    address public mlpManager;

    address public stakedMineTracker;
    address public bonusMineTracker;
    address public feeMineTracker;

    address public feeMlpTracker;
    address public stakedMlpTracker;

    address public stakedMineDistributor;
    address public stakedMlpDistributor;

    address public allMine;
    address public bnMine;

    address public mineVester;
    address public mlpVester;

    function initialize(
        ITimelock _timelock,
        address _rewardRouter,
        address _mlpManager,
        address _stakedMineTracker,
        address _bonusMineTracker,
        address _feeMineTracker,
        address _feeMlpTracker,
        address _stakedMlpTracker,
        address _stakedMineDistributor,
        address _stakedMlpDistributor,
        address _allMine,
        address _bnMine,
        address _mineVester,
        address _mlpVester
    ) external onlyGov {
        require(!isInitialized, "RewardManager: already initialized");
        isInitialized = true;

        timelock = _timelock;
        rewardRouter = _rewardRouter;

        mlpManager = _mlpManager;

        stakedMineTracker = _stakedMineTracker;
        bonusMineTracker = _bonusMineTracker;
        feeMineTracker = _feeMineTracker;

        feeMlpTracker = _feeMlpTracker;
        stakedMlpTracker = _stakedMlpTracker;

        stakedMineDistributor = _stakedMineDistributor;
        stakedMlpDistributor = _stakedMlpDistributor;

        allMine = _allMine;
        bnMine = _bnMine;

        mineVester = _mineVester;
        mlpVester = _mlpVester;
    }

    // function updateAllMineHandlers() external onlyGov {
    //     timelock.managedSetHandler(allMine, rewardRouter, true);

    //     timelock.managedSetHandler(allMine, stakedMineDistributor, true);
    //     timelock.managedSetHandler(allMine, stakedMlpDistributor, true);

    //     timelock.managedSetHandler(allMine, stakedMineTracker, true);
    //     timelock.managedSetHandler(allMine, stakedMlpTracker, true);

    //     timelock.managedSetHandler(allMine, mineVester, true);
    //     timelock.managedSetHandler(allMine, mlpVester, true);
    // }

    // function enableRewardRouter() external onlyGov {
    //     timelock.managedSetHandler(mlpManager, rewardRouter, true);

    //     timelock.managedSetHandler(stakedMineTracker, rewardRouter, true);
    //     timelock.managedSetHandler(bonusMineTracker, rewardRouter, true);
    //     timelock.managedSetHandler(feeMineTracker, rewardRouter, true);

    //     timelock.managedSetHandler(feeMlpTracker, rewardRouter, true);
    //     timelock.managedSetHandler(stakedMlpTracker, rewardRouter, true);

    //     timelock.managedSetHandler(allMine, rewardRouter, true);

    //     timelock.managedSetMinter(bnMine, rewardRouter, true);

    //     timelock.managedSetMinter(allMine, mineVester, true);
    //     timelock.managedSetMinter(allMine, mlpVester, true);

    //     timelock.managedSetHandler(mineVester, rewardRouter, true);
    //     timelock.managedSetHandler(mlpVester, rewardRouter, true);

    //     timelock.managedSetHandler(feeMineTracker, mineVester, true);
    //     timelock.managedSetHandler(stakedMlpTracker, mlpVester, true);
    // }
}
