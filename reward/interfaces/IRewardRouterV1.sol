// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IRewardRouter {
    function stakeMine(uint256 _amount) external;
    
    function stakeAllMine(uint256 _amount) external;

    function unstakeMine(uint256 _amount) external;

    function unstakeAllMine(uint256 _amount) external;

    function signalTransfer(address _receiver) external;

    function compound() external;

    function handleRewards(
        bool _shouldClaimMine,
        bool _shouldStakeMine,
        bool _shouldClaimAllMine,
        bool _shouldStakeAllMine,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth,
        bool _shouldAddIntoMLP,
        bool _shouldConvertMineAndStake
    ) external returns (uint256 amountOut);
}
