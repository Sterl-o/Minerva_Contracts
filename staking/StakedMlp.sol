// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";

import "../core/interfaces/IMlpManager.sol";

import "./interfaces/IRewardTracker.sol";

contract StakedMlp {
    using SafeMath for uint256;

    string public constant name = "StakedMlp";
    string public constant symbol = "sMLP";
    uint8 public constant decimals = 18;

    address public mlp;
    IMlpManager public mlpManager;
    address public stakedMlpTracker;
    address public feeMlpTracker;

    mapping(address => mapping(address => uint256)) public allowances;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        address _mlp,
        IMlpManager _mlpManager,
        address _stakedMlpTracker,
        address _feeMlpTracker
    ) public {
        mlp = _mlp;
        mlpManager = _mlpManager;
        stakedMlpTracker = _stakedMlpTracker;
        feeMlpTracker = _feeMlpTracker;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "StakedMlp: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function balanceOf(address _account) external view returns (uint256) {
        IRewardTracker(stakedMlpTracker).depositBalances(_account, mlp);
    }

    function totalSupply() external view returns (uint256) {
        IERC20(stakedMlpTracker).totalSupply();
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        require(_owner != address(0), "StakedMlp: approve from the zero address");
        require(_spender != address(0), "StakedMlp: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private {
        require(_sender != address(0), "StakedMlp: transfer from the zero address");
        require(_recipient != address(0), "StakedMlp: transfer to the zero address");

        require(mlpManager.lastAddedAt(_sender).add(mlpManager.cooldownDuration()) <= block.timestamp, "StakedMlp: cooldown duration not yet passed");

        IRewardTracker(stakedMlpTracker).unstakeForAccount(_sender, feeMlpTracker, _amount, _sender);
        IRewardTracker(feeMlpTracker).unstakeForAccount(_sender, mlp, _amount, _sender);

        IRewardTracker(feeMlpTracker).stakeForAccount(_sender, _recipient, mlp, _amount);
        IRewardTracker(stakedMlpTracker).stakeForAccount(_recipient, _recipient, feeMlpTracker, _amount);
    }
}
