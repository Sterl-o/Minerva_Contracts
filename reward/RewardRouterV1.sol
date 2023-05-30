// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/token/TransferHelper.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IMlpManager.sol";
import "../core/interfaces/IVault.sol";
import "../access/Governable.sol";
import "../peripherals/interfaces/ISwapRouter.sol";

contract RewardRouter is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;


    ISwapRouter public immutable swapRouter;

    address public vault;
    address public usdc;
    address public mine;
    address public allMine;
    address public bnMine;

    address public mlp; // MINE Liquidity Provider token

    address public stakedMineTracker;
    address public bonusMineTracker;
    address public feeMineTracker;

    address public stakedMlpTracker;
    address public feeMlpTracker;

    address public mlpManager;

    address public mineVester;
    address public mlpVester;

    mapping(address => address) public pendingReceivers;

    event StakeMine(address account, address token, uint256 amount);
    event UnstakeMine(address account, address token, uint256 amount);

    event StakeMlp(address account, uint256 amount);
    event UnstakeMlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    uint24 public constant MINE_USDC_POOL_FEE = 10000;

    constructor(address _swapRouter,
        address _weth,
        address _mine,
        address _allMine,
        address _bnMine,
        address _mlp,       
        address _usdc,
        address _vault    
    ) public{
        swapRouter = ISwapRouter(_swapRouter);
        weth = _weth;
        mine = _mine;
        allMine = _allMine;
        bnMine = _bnMine;
        mlp = _mlp;        
        usdc = _usdc;
        vault = _vault;
    }

    function initialize(
        address _stakedMineTracker,
        address _bonusMineTracker,
        address _feeMineTracker,
        address _feeMlpTracker,
        address _stakedMlpTracker,
        address _mlpManager,
        address _mineVester,
        address _mlpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        stakedMineTracker = _stakedMineTracker;
        bonusMineTracker = _bonusMineTracker;
        feeMineTracker = _feeMineTracker;

        feeMlpTracker = _feeMlpTracker;
        stakedMlpTracker = _stakedMlpTracker;

        mlpManager = _mlpManager;

        mineVester = _mineVester;
        mlpVester = _mlpVester;

    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeMineForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _mine = mine;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeMine(msg.sender, _accounts[i], _mine, _amounts[i]);
        }
    }

    function stakeMineForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeMine(msg.sender, _account, mine, _amount);
    }

    function stakeMine(uint256 _amount) external nonReentrant {
        _stakeMine(msg.sender, msg.sender, mine, _amount);
    }

    function stakeAllMine(uint256 _amount) external nonReentrant {
        _stakeMine(msg.sender, msg.sender, allMine, _amount);
    }

    function unstakeMine(uint256 _amount) external nonReentrant {
        _unstakeMine(msg.sender, mine, _amount, true);
    }

    function unstakeAllMine(uint256 _amount) external nonReentrant {
        _unstakeMine(msg.sender, allMine, _amount, true);
    }

    function mintAndStakeMlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdm,
        uint256 _minMlp
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 mlpAmount = IMlpManager(mlpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdm, _minMlp);
        IRewardTracker(feeMlpTracker).stakeForAccount(account, account, mlp, mlpAmount);
        IRewardTracker(stakedMlpTracker).stakeForAccount(account, account, feeMlpTracker, mlpAmount);

        emit StakeMlp(account, mlpAmount);

        return mlpAmount;
    }

    function mintAndStakeMlpETH(uint256 _minUsdm, uint256 _minMlp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        return _mintAndStakeMlpETH(msg.value,_minUsdm, _minMlp);
    }

    function _mintAndStakeMlpETH(uint256 _amount,uint256 _minUsdm, uint256 _minMlp) private returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IERC20(weth).approve(mlpManager, _amount);

        address account = msg.sender;
        uint256 mlpAmount = IMlpManager(mlpManager).addLiquidityForAccount(address(this), account, weth, _amount, _minUsdm, _minMlp);

        IRewardTracker(feeMlpTracker).stakeForAccount(account, account, mlp, mlpAmount);
        IRewardTracker(stakedMlpTracker).stakeForAccount(account, account, feeMlpTracker, mlpAmount);

        emit StakeMlp(account, mlpAmount);

        return mlpAmount;
    }

    function unstakeAndRedeemMlp(
        address _tokenOut,
        uint256 _mlpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_mlpAmount > 0, "RewardRouter: invalid _mlpAmount");

        address account = msg.sender;
        IRewardTracker(stakedMlpTracker).unstakeForAccount(account, feeMlpTracker, _mlpAmount, account);
        IRewardTracker(feeMlpTracker).unstakeForAccount(account, mlp, _mlpAmount, account);
        uint256 amountOut = IMlpManager(mlpManager).removeLiquidityForAccount(account, _tokenOut, _mlpAmount, _minOut, _receiver);

        emit UnstakeMlp(account, _mlpAmount);

        return amountOut;
    }

    function unstakeAndRedeemMlpETH(
        uint256 _mlpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        require(_mlpAmount > 0, "RewardRouter: invalid _mlpAmount");

        address account = msg.sender;
        IRewardTracker(stakedMlpTracker).unstakeForAccount(account, feeMlpTracker, _mlpAmount, account);
        IRewardTracker(feeMlpTracker).unstakeForAccount(account, mlp, _mlpAmount, account);
        uint256 amountOut = IMlpManager(mlpManager).removeLiquidityForAccount(account, weth, _mlpAmount, _minOut, address(this));

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeMlp(account, _mlpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeMineTracker).claimForAccount(account, account);
        IRewardTracker(feeMlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedMineTracker).claimForAccount(account, account);
        IRewardTracker(stakedMlpTracker).claimForAccount(account, account);
    }

    function claimAllMine() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedMineTracker).claimForAccount(account, account);
        IRewardTracker(stakedMlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeMineTracker).claimForAccount(account, account);
        IRewardTracker(feeMlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

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
    ) external nonReentrant returns (uint256 amountOut) {
        address account = msg.sender;

        uint256 mineAmount = 0;
        if (_shouldClaimMine) {
            uint256 mineAmount0 = IVester(mineVester).claimForAccount(account, account);
            uint256 mineAmount1 = IVester(mlpVester).claimForAccount(account, account);
            mineAmount = mineAmount0.add(mineAmount1);
        }

        if (_shouldStakeMine && mineAmount > 0) {
            _stakeMine(account, account, mine, mineAmount);
        }

        uint256 allMineAmount = 0;
        if (_shouldClaimAllMine) {
            uint256 allMineAmount0 = IRewardTracker(stakedMineTracker).claimForAccount(account, account);
            uint256 allMineAmount1 = IRewardTracker(stakedMlpTracker).claimForAccount(account, account);
            allMineAmount = allMineAmount0.add(allMineAmount1);
        }

        if (_shouldStakeAllMine && allMineAmount > 0) {
            _stakeMine(account, account, allMine, allMineAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnMineAmount = IRewardTracker(bonusMineTracker).claimForAccount(account, account);
            if (bnMineAmount > 0) {
                IRewardTracker(feeMineTracker).stakeForAccount(account, account, bnMine, bnMineAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth || _shouldAddIntoMLP || _shouldConvertMineAndStake) {
                uint256 weth0 = IRewardTracker(feeMineTracker).claimForAccount(account, address(this));
                uint256 weth1 = IRewardTracker(feeMlpTracker).claimForAccount(account, address(this));

                uint256 wethAmount = weth0.add(weth1);
                

                if(_shouldAddIntoMLP){
                    amountOut = _mintAndStakeMlpETH(wethAmount,0,0);
                }else if(_shouldConvertMineAndStake){
                    //convert weth->usdc->mine and stake

                    IERC20(weth).safeTransfer(vault, wethAmount);

                    //convert weth->usdc via vault
                    uint256 usdcAmountOut = IVault(vault).swap(weth, usdc, address(this));

                    //convert usdc->mine via uniswap
                     uint256 mineAmountOut = _swapExactInputSingle(usdcAmountOut);

                    if (mineAmountOut > 0) {
                        TransferHelper.safeApprove(mine, stakedMineTracker, mineAmountOut);
                        _stakeMine(address(this), account, mine, mineAmountOut);
                        amountOut = mineAmountOut;
                    }

                }else{
                    IWETH(weth).withdraw(wethAmount);
                    payable(account).sendValue(wethAmount);
                }
            } else {
                IRewardTracker(feeMineTracker).claimForAccount(account, account);
                IRewardTracker(feeMlpTracker).claimForAccount(account, account);
            }
        }
    }

    function _swapExactInputSingle(uint256 amountIn) private returns (uint256 amountOut) {
        TransferHelper.safeApprove(usdc, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: usdc,
                tokenOut: mine,
                fee: MINE_USDC_POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(IERC20(mineVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(mlpVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(mineVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(mlpVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedMine = IRewardTracker(stakedMineTracker).depositBalances(_sender, mine);
        if (stakedMine > 0) {
            _unstakeMine(_sender, mine, stakedMine, false);
            _stakeMine(_sender, receiver, mine, stakedMine);
        }

        uint256 stakedAllMine = IRewardTracker(stakedMineTracker).depositBalances(_sender, allMine);
        if (stakedAllMine > 0) {
            _unstakeMine(_sender, allMine, stakedAllMine, false);
            _stakeMine(_sender, receiver, allMine, stakedAllMine);
        }

        uint256 stakedBnMine = IRewardTracker(feeMineTracker).depositBalances(_sender, bnMine);
        if (stakedBnMine > 0) {
            IRewardTracker(feeMineTracker).unstakeForAccount(_sender, bnMine, stakedBnMine, _sender);
            IRewardTracker(feeMineTracker).stakeForAccount(_sender, receiver, bnMine, stakedBnMine);
        }

        uint256 allMineBalance = IERC20(allMine).balanceOf(_sender);
        if (allMineBalance > 0) {
            IERC20(allMine).transferFrom(_sender, receiver, allMineBalance);
        }

        uint256 mlpAmount = IRewardTracker(feeMlpTracker).depositBalances(_sender, mlp);
        if (mlpAmount > 0) {
            IRewardTracker(stakedMlpTracker).unstakeForAccount(_sender, feeMlpTracker, mlpAmount, _sender);
            IRewardTracker(feeMlpTracker).unstakeForAccount(_sender, mlp, mlpAmount, _sender);

            IRewardTracker(feeMlpTracker).stakeForAccount(_sender, receiver, mlp, mlpAmount);
            IRewardTracker(stakedMlpTracker).stakeForAccount(receiver, receiver, feeMlpTracker, mlpAmount);
        }

        IVester(mineVester).transferStakeValues(_sender, receiver);
        IVester(mlpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(IRewardTracker(stakedMineTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedMineTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedMineTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedMineTracker.cumulativeRewards > 0");

        require(IRewardTracker(bonusMineTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: bonusMineTracker.averageStakedAmounts > 0");
        require(IRewardTracker(bonusMineTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: bonusMineTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeMineTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeMineTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeMineTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeMineTracker.cumulativeRewards > 0");

        require(IVester(mineVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: mineVester.transferredAverageStakedAmounts > 0");
        require(IVester(mineVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: mineVester.transferredCumulativeRewards > 0");

        require(IRewardTracker(stakedMlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedMlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedMlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedMlpTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeMlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeMlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeMlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeMlpTracker.cumulativeRewards > 0");

        require(IVester(mlpVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: mineVester.transferredAverageStakedAmounts > 0");
        require(IVester(mlpVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: mineVester.transferredCumulativeRewards > 0");

        require(IERC20(mineVester).balanceOf(_receiver) == 0, "RewardRouter: mineVester.balance > 0");
        require(IERC20(mlpVester).balanceOf(_receiver) == 0, "RewardRouter: mlpVester.balance > 0");
    }

    function _compound(address _account) private {
        _compoundMine(_account);
        _compoundMlp(_account);
    }

    function _compoundMine(address _account) private {
        uint256 allMineAmount = IRewardTracker(stakedMineTracker).claimForAccount(_account, _account);
        if (allMineAmount > 0) {
            _stakeMine(_account, _account, allMine, allMineAmount);
        }

        uint256 bnMineAmount = IRewardTracker(bonusMineTracker).claimForAccount(_account, _account);
        if (bnMineAmount > 0) {
            IRewardTracker(feeMineTracker).stakeForAccount(_account, _account, bnMine, bnMineAmount);
        }
    }

    function _compoundMlp(address _account) private {
        uint256 allMineAmount = IRewardTracker(stakedMlpTracker).claimForAccount(_account, _account);
        if (allMineAmount > 0) {
            _stakeMine(_account, _account, allMine, allMineAmount);
        }
    }

    function _stakeMine(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedMineTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusMineTracker).stakeForAccount(_account, _account, stakedMineTracker, _amount);
        IRewardTracker(feeMineTracker).stakeForAccount(_account, _account, bonusMineTracker, _amount);

        emit StakeMine(_account, _token, _amount);
    }

    function _unstakeMine(
        address _account,
        address _token,
        uint256 _amount,
        bool _shouldReduceBnMine
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedMineTracker).stakedAmounts(_account);

        IRewardTracker(feeMineTracker).unstakeForAccount(_account, bonusMineTracker, _amount, _account);
        IRewardTracker(bonusMineTracker).unstakeForAccount(_account, stakedMineTracker, _amount, _account);
        IRewardTracker(stakedMineTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnMine) {
            uint256 bnMineAmount = IRewardTracker(bonusMineTracker).claimForAccount(_account, _account);
            if (bnMineAmount > 0) {
                IRewardTracker(feeMineTracker).stakeForAccount(_account, _account, bnMine, bnMineAmount);
            }

            uint256 stakedBnMine = IRewardTracker(feeMineTracker).depositBalances(_account, bnMine);
            if (stakedBnMine > 0) {
                uint256 reductionAmount = stakedBnMine.mul(_amount).div(balance);
                IRewardTracker(feeMineTracker).unstakeForAccount(_account, bnMine, reductionAmount, _account);
                IMintable(bnMine).burn(_account, reductionAmount);
            }
        }

        emit UnstakeMine(_account, _token, _amount);
    }
}
