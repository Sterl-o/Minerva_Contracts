// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../tokens/interfaces/IWETH.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/Address.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/IterableMapping.sol";

import "./interfaces/IRouter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IOrderBook.sol";


contract OrderBook is ReentrancyGuard, IOrderBook {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public constant PRICE_PRECISION = 1e30;
    uint256 public constant USDM_PRECISION = 1e18;


    itmap public orderList;
    // Apply library functions to the data type.
    using IterableMapping for itmap;


    struct IncreaseOrder {
        address account;
        address purchaseToken;
        uint256 purchaseTokenAmount;
        address collateralToken;
        address indexToken;
        uint256 sizeDelta;
        bool isLong;
        uint256 triggerPrice;
        bool triggerAboveThreshold;
        uint256 executionFee;
    }
    struct DecreaseOrder {
        address account;
        address collateralToken;
        address receiveToken;
        uint256 collateralDelta;
        address indexToken;
        uint256 sizeDelta;
        bool isLong;
        uint256 triggerPrice;
        bool triggerAboveThreshold;
        uint256 minOut;
        bool withdrawETH;
        uint256 executionFee;
    }
    struct SwapOrder {
        address account;
        address[] path;
        uint256 amountIn;
        uint256 minOut;
        uint256 triggerRatio;
        bool triggerAboveThreshold;
        bool shouldUnwrap;
        uint256 executionFee;
    }

    mapping(address => mapping(uint256 => IncreaseOrder)) public increaseOrders;
    mapping(address => uint256) public increaseOrdersIndex;
    mapping(address => mapping(uint256 => DecreaseOrder)) public decreaseOrders;
    mapping(address => uint256) public decreaseOrdersIndex;
    mapping(address => mapping(uint256 => SwapOrder)) public swapOrders;
    mapping(address => uint256) public swapOrdersIndex;

    address public gov;
    address public weth;
    address public usdm;
    address public router;
    address public vault;
    address public orderExecutor;


    uint256 public minExecutionFee;
    uint256 public minPurchaseTokenAmountUsd;
    bool public isInitialized = false;
    bool public chainlinkOrderExecutionActive = false;

    event CreateIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address purchaseToken,
        uint256 purchaseTokenAmount,
        address collateralToken,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee
    );
    event CancelIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address purchaseToken,
        uint256 purchaseTokenAmount,
        address collateralToken,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee
    );
    event ExecuteIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address purchaseToken,
        uint256 purchaseTokenAmount,
        address collateralToken,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee,
        uint256 executionPrice
    );
    event UpdateIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        address indexToken,
        bool isLong,
        uint256 sizeDelta,
        uint256 triggerPrice,
        bool triggerAboveThreshold
    );
    event CreateDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        address receiveToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee
    );

    event CancelDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee
    );
    event ExecuteDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee,
        uint256 executionPrice
    );
    event UpdateDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold
    );
    event CreateSwapOrder(
        address indexed account,
        uint256 orderIndex,
        address[] path,
        uint256 amountIn,
        uint256 minOut,
        uint256 triggerRatio,
        bool triggerAboveThreshold,
        bool shouldUnwrap,
        uint256 executionFee
    );
    event CancelSwapOrder(
        address indexed account,
        uint256 orderIndex,
        address[] path,
        uint256 amountIn,
        uint256 minOut,
        uint256 triggerRatio,
        bool triggerAboveThreshold,
        bool shouldUnwrap,
        uint256 executionFee
    );
    event UpdateSwapOrder(
        address indexed account,
        uint256 ordexIndex,
        address[] path,
        uint256 amountIn,
        uint256 minOut,
        uint256 triggerRatio,
        bool triggerAboveThreshold,
        bool shouldUnwrap,
        uint256 executionFee
    );
    event ExecuteSwapOrder(
        address indexed account,
        uint256 orderIndex,
        address[] path,
        uint256 amountIn,
        uint256 minOut,
        uint256 amountOut,
        uint256 triggerRatio,
        bool triggerAboveThreshold,
        bool shouldUnwrap,
        uint256 executionFee
    );

    constructor() public {
        gov = msg.sender;
    }

    function _onlyGov() private view {
        require(msg.sender == gov, "OB: forbidden");
    }

    function _onlyOrderExecutor() private view {
        require(msg.sender == orderExecutor, "OB: forbidden");
    }

    function initialize(
        address _router,
        address _vault,
        address _weth,
        address _usdm,
        uint256 _minExecutionFee,
        uint256 _minPurchaseTokenAmountUsd
    ) external {
        _onlyGov();
        require(!isInitialized, "OB: error");
        isInitialized = true;

        router = _router;
        vault = _vault;
        weth = _weth;
        usdm = _usdm;
        minExecutionFee = _minExecutionFee;
        minPurchaseTokenAmountUsd = _minPurchaseTokenAmountUsd;

    }

    receive() external payable {
        require(msg.sender == weth, "OB: invalid sender");
    }

    function setOrderExecutor(
        address _orderExecutor
    )external  {
        _onlyGov();
        orderExecutor = _orderExecutor;

    }

    function _addToOpenOrders(address _account, uint256 _index, OrderType _type) internal {
        uint256 orderKey = getOrderKey(_account,  _index,  _type);
        Orders memory order = Orders(
            _account,
            _index,
            _type
        );
        orderList.insert(orderKey,order);
    }

    function _removeFromOpenOrders(address _account, uint256 _index, OrderType _type) internal {
        uint256 orderKey = getOrderKey(_account,  _index,  _type);
        orderList.remove(orderKey);
    }

    function getOrderKey(address _account, uint256 _index, OrderType _type) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_account, _index, _type)));
    }


    function setMinExecutionFee(uint256 _minExecutionFee) external  {
        _onlyGov();
        minExecutionFee = _minExecutionFee;

    }
    function setChainlinkOrderExecutionActive(bool _chainlinkOrderExecutionActive) external  {
        _onlyGov();
        chainlinkOrderExecutionActive = _chainlinkOrderExecutionActive;


    }
    function setMinPurchaseTokenAmountUsd(uint256 _minPurchaseTokenAmountUsd) external  {
        _onlyGov();
        minPurchaseTokenAmountUsd = _minPurchaseTokenAmountUsd;

    }

    function setGov(address _gov) external  {
        _onlyGov();
        gov = _gov;

    }

    function getSwapOrder(address _account, uint256 _orderIndex)
        public
        view
        override
        returns (
            address path0,
            address path1,
            address path2,
            uint256 amountIn,
            uint256 minOut,
            uint256 triggerRatio,
            bool triggerAboveThreshold,
            bool shouldUnwrap,
            uint256 executionFee
        )
    {
        SwapOrder memory order = swapOrders[_account][_orderIndex];
        return (
            order.path.length > 0 ? order.path[0] : address(0),
            order.path.length > 1 ? order.path[1] : address(0),
            order.path.length > 2 ? order.path[2] : address(0),
            order.amountIn,
            order.minOut,
            order.triggerRatio,
            order.triggerAboveThreshold,
            order.shouldUnwrap,
            order.executionFee
        );
    }

    function createSwapOrder(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _triggerRatio, // tokenB / tokenA
        bool _triggerAboveThreshold,
        uint256 _executionFee,
        bool _shouldWrap,
        bool _shouldUnwrap
    ) external payable nonReentrant {
        require(_path.length == 2 || _path.length == 3, "OB: invalid _path.length");
        require(_path[0] != _path[_path.length - 1], "OB: invalid _path");
        require(_path[0] != usdm && _path[_path.length - 1] != usdm, "OB: invalid token");
        require(_amountIn > 0, "OB: invalid _amountIn");
        require(_executionFee >= minExecutionFee, "OB: insufficient execution fee");

        // always need this call because of mandatory executionFee user has to transfer in ETH
        _transferInETH();

        if (_shouldWrap) {
            require(_path[0] == weth, "OB: only weth could be wrapped");
            require(msg.value == _executionFee.add(_amountIn), "OB: incorrect value transferred");
        } else {
            require(msg.value == _executionFee, "OB: incorrect execution fee transferred");
            IRouter(router).pluginTransfer(_path[0], msg.sender, address(this), _amountIn);
        }

        _createSwapOrder(msg.sender, _path, _amountIn, _minOut, _triggerRatio, _triggerAboveThreshold, _shouldUnwrap, _executionFee);
    }

    function _createSwapOrder(
        address _account,
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _triggerRatio,
        bool _triggerAboveThreshold,
        bool _shouldUnwrap,
        uint256 _executionFee
    ) private {
        uint256 _orderIndex = swapOrdersIndex[_account];
        SwapOrder memory order = SwapOrder(_account, _path, _amountIn, _minOut, _triggerRatio, _triggerAboveThreshold, _shouldUnwrap, _executionFee);
        swapOrdersIndex[_account] = _orderIndex.add(1);
        swapOrders[_account][_orderIndex] = order;
        _addToOpenOrders(_account,_orderIndex,OrderType.SWAP); 

        emit CreateSwapOrder(_account, _orderIndex, _path, _amountIn, _minOut, _triggerRatio, _triggerAboveThreshold, _shouldUnwrap, _executionFee);
    }

    function cancelMultiple(
        uint256[] memory _swapOrderIndexes,
        uint256[] memory _increaseOrderIndexes,
        uint256[] memory _decreaseOrderIndexes
    ) external {
        for (uint256 i = 0; i < _swapOrderIndexes.length; i++) {
            cancelSwapOrder(_swapOrderIndexes[i]);
        }
        for (uint256 i = 0; i < _increaseOrderIndexes.length; i++) {
            cancelIncreaseOrder(_increaseOrderIndexes[i]);
        }
        for (uint256 i = 0; i < _decreaseOrderIndexes.length; i++) {
            cancelDecreaseOrder(_decreaseOrderIndexes[i]);
        }
    }

    function cancelSwapOrder(uint256 _orderIndex) public nonReentrant {
        SwapOrder memory order = swapOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OB: non-existent order");

        delete swapOrders[msg.sender][_orderIndex];
        _removeFromOpenOrders(msg.sender,_orderIndex,OrderType.SWAP); 

        if (order.path[0] == weth) {
            _transferOutETH(order.executionFee.add(order.amountIn), msg.sender);
        } else {
            IERC20(order.path[0]).safeTransfer(msg.sender, order.amountIn);
            _transferOutETH(order.executionFee, msg.sender);
        }

        emit CancelSwapOrder(
            msg.sender,
            _orderIndex,
            order.path,
            order.amountIn,
            order.minOut,
            order.triggerRatio,
            order.triggerAboveThreshold,
            order.shouldUnwrap,
            order.executionFee
        );
    }

    function validateSwapOrderPriceWithTriggerAboveThreshold(address[] memory _path, uint256 _triggerRatio) public view returns (bool) {
        require(_path.length == 2 || _path.length == 3, "OB: invalid _path.length");

        // limit orders don't need this validation because minOut is enough
        // so this validation handles scenarios for stop orders only
        // when a user wants to swap when a price of tokenB increases relative to tokenA
        address tokenA = _path[0];
        address tokenB = _path[_path.length - 1];
        uint256 tokenAPrice;
        uint256 tokenBPrice;

        tokenAPrice = IVault(vault).getMinPrice(tokenA);
        tokenBPrice = IVault(vault).getMaxPrice(tokenB);

        uint256 currentRatio = tokenBPrice.mul(PRICE_PRECISION).div(tokenAPrice);

        bool isValid = currentRatio > _triggerRatio;
        return isValid;
    }

    function updateSwapOrder(
        uint256 _orderIndex,
        uint256 _minOut,
        uint256 _triggerRatio,
        bool _triggerAboveThreshold
    ) external nonReentrant {
        SwapOrder storage order = swapOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OB: non-existent order");

        order.minOut = _minOut;
        order.triggerRatio = _triggerRatio;
        order.triggerAboveThreshold = _triggerAboveThreshold;

        emit UpdateSwapOrder(msg.sender, _orderIndex, order.path, order.amountIn, _minOut, _triggerRatio, _triggerAboveThreshold, order.shouldUnwrap, order.executionFee);
    }

    function executeSwapOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external override nonReentrant {
        _onlyOrderExecutor();
        SwapOrder memory order = swapOrders[_account][_orderIndex];
        require(order.account != address(0), "OB: non-existent order");

        if (order.triggerAboveThreshold) {
            // gas optimisation
            // order.minAmount should prevent wrong price execution in case of simple limit order
            require(validateSwapOrderPriceWithTriggerAboveThreshold(order.path, order.triggerRatio), "OB: invalid price for execution");
        }

        delete swapOrders[_account][_orderIndex];
        _removeFromOpenOrders(_account,_orderIndex,OrderType.SWAP);

        IERC20(order.path[0]).safeTransfer(vault, order.amountIn);

        uint256 _amountOut;
        if (order.path[order.path.length - 1] == weth && order.shouldUnwrap) {
            _amountOut = _swap(order.path, order.minOut, address(this));
            _transferOutETH(_amountOut, payable(order.account));
        } else {
            _amountOut = _swap(order.path, order.minOut, order.account);
        }

        // pay executor
        _transferOutETH(order.executionFee, _feeReceiver);

        emit ExecuteSwapOrder(
            _account,
            _orderIndex,
            order.path,
            order.amountIn,
            order.minOut,
            _amountOut,
            order.triggerRatio,
            order.triggerAboveThreshold,
            order.shouldUnwrap,
            order.executionFee
        );
    }

    function validatePositionOrderPrice(
        bool _triggerAboveThreshold,
        uint256 _triggerPrice,
        address _indexToken,
        bool _maximizePrice,
        bool _raise
    ) public view returns (uint256, bool) {
        uint256 currentPrice = _maximizePrice ? IVault(vault).getMaxPrice(_indexToken) : IVault(vault).getMinPrice(_indexToken);
        bool isPriceValid = _triggerAboveThreshold ? currentPrice > _triggerPrice : currentPrice < _triggerPrice;
        if (_raise) {
            require(isPriceValid, "OB: invalid price for execution");
        }
        return (currentPrice, isPriceValid);
    }

    function getDecreaseOrder(address _account, uint256 _orderIndex)
        public
        view
        override
        returns (
            address collateralToken,
            uint256 collateralDelta,
            address indexToken,
            uint256 sizeDelta,
            bool isLong,
            uint256 triggerPrice,
            bool triggerAboveThreshold,
            uint256 executionFee
        )
    {
        DecreaseOrder memory order = decreaseOrders[_account][_orderIndex];
        return (order.collateralToken, order.collateralDelta, order.indexToken, order.sizeDelta, order.isLong, order.triggerPrice, order.triggerAboveThreshold, order.executionFee);
    }

    function getDecreaseOrderV2(address _account, uint256 _orderIndex)
        public
        view
        returns (
            address collateralToken,
            address receiveToken,
            uint256 collateralDelta,
            address indexToken,
            uint256 sizeDelta,
            bool isLong,
            uint256 triggerPrice,
            bool triggerAboveThreshold,
            uint256 executionFee
        )
    {
        DecreaseOrder memory order = decreaseOrders[_account][_orderIndex];
        return (order.collateralToken, order.receiveToken, order.collateralDelta, order.indexToken, order.sizeDelta, order.isLong, order.triggerPrice, order.triggerAboveThreshold, order.executionFee);
    }

    function getIncreaseOrder(address _account, uint256 _orderIndex)
        public
        view
        override
        returns (
            address purchaseToken,
            uint256 purchaseTokenAmount,
            address collateralToken,
            address indexToken,
            uint256 sizeDelta,
            bool isLong,
            uint256 triggerPrice,
            bool triggerAboveThreshold,
            uint256 executionFee
        )
    {
        IncreaseOrder memory order = increaseOrders[_account][_orderIndex];
        return (
            order.purchaseToken,
            order.purchaseTokenAmount,
            order.collateralToken,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee
        );
    }

    function createIncreaseOrder(
        address[] memory _path,
        uint256 _amountIn,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        address _collateralToken,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold,
        uint256 _executionFee,
        bool _shouldWrap
    ) external payable nonReentrant {
        // always need this call because of mandatory executionFee user has to transfer in ETH
        _transferInETH();

        require(_executionFee >= minExecutionFee, "OB: insufficient execution fee");
        if (_shouldWrap) {
            require(_path[0] == weth, "OB: only weth could be wrapped");
            require(msg.value == _executionFee.add(_amountIn), "OB: incorrect value transferred");
        } else {
            require(msg.value == _executionFee, "OB: incorrect execution fee transferred");
            IRouter(router).pluginTransfer(_path[0], msg.sender, address(this), _amountIn);
        }

        address _purchaseToken = _path[_path.length - 1];
        uint256 _purchaseTokenAmount;
        if (_path.length > 1) {
            require(_path[0] != _purchaseToken, "OB: invalid _path");
            IERC20(_path[0]).safeTransfer(vault, _amountIn);
            _purchaseTokenAmount = _swap(_path, _minOut, address(this));
        } else {
            _purchaseTokenAmount = _amountIn;
        }

        {
            uint256 _purchaseTokenAmountUsd = IVault(vault).tokenToUsdMin(_purchaseToken, _purchaseTokenAmount);
            require(_purchaseTokenAmountUsd >= minPurchaseTokenAmountUsd, "OB: insufficient collateral");
        }

        _createIncreaseOrder(
            msg.sender,
            _purchaseToken,
            _purchaseTokenAmount,
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            _executionFee
        );
    }

    function _createIncreaseOrder(
        address _account,
        address _purchaseToken,
        uint256 _purchaseTokenAmount,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold,
        uint256 _executionFee
    ) private {
        uint256 _orderIndex = increaseOrdersIndex[_account];
        IncreaseOrder memory order = IncreaseOrder(
            _account,
            _purchaseToken,
            _purchaseTokenAmount,
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            _executionFee
        );
        increaseOrdersIndex[_account] = _orderIndex.add(1);
        increaseOrders[_account][_orderIndex] = order;
        _addToOpenOrders(_account,_orderIndex,OrderType.INCREASE);
            emit CreateIncreaseOrder(
                _account,
                _orderIndex,
                _purchaseToken,
                _purchaseTokenAmount,
                _collateralToken,
                _indexToken,
                _sizeDelta,
                _isLong,
                _triggerPrice,
                _triggerAboveThreshold,
                _executionFee
            );
    }

    function updateIncreaseOrder(
        uint256 _orderIndex,
        uint256 _sizeDelta,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external nonReentrant {
        IncreaseOrder storage order = increaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OB: non-existent order");

        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        order.sizeDelta = _sizeDelta;

        emit UpdateIncreaseOrder(msg.sender, _orderIndex, order.collateralToken, order.indexToken, order.isLong, _sizeDelta, _triggerPrice, _triggerAboveThreshold);
    }

    function cancelIncreaseOrder(uint256 _orderIndex) public nonReentrant {
        IncreaseOrder memory order = increaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OB: non-existent order");

        delete increaseOrders[msg.sender][_orderIndex];
        _removeFromOpenOrders(msg.sender,_orderIndex,OrderType.INCREASE);

        if (order.purchaseToken == weth) {
            _transferOutETH(order.executionFee.add(order.purchaseTokenAmount), msg.sender);
        } else {
            IERC20(order.purchaseToken).safeTransfer(msg.sender, order.purchaseTokenAmount);
            _transferOutETH(order.executionFee, msg.sender);
        }

        emit CancelIncreaseOrder(
            order.account,
            _orderIndex,
            order.purchaseToken,
            order.purchaseTokenAmount,
            order.collateralToken,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee
        );
    }

    function executeIncreaseOrder(
        address _address,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external override nonReentrant {
        _onlyOrderExecutor();
        IncreaseOrder memory order = increaseOrders[_address][_orderIndex];
        require(order.account != address(0), "OB: non-existent order");

        // increase long should use max price
        // increase short should use min price
        (uint256 currentPrice, ) = validatePositionOrderPrice(order.triggerAboveThreshold, order.triggerPrice, order.indexToken, order.isLong, true);

        delete increaseOrders[_address][_orderIndex];
        _removeFromOpenOrders(_address,_orderIndex,OrderType.INCREASE);

        IERC20(order.purchaseToken).safeTransfer(vault, order.purchaseTokenAmount);

        if (order.purchaseToken != order.collateralToken) {
            address[] memory path = new address[](2);
            path[0] = order.purchaseToken;
            path[1] = order.collateralToken;

            uint256 amountOut = _swap(path, 0, address(this));
            IERC20(order.collateralToken).safeTransfer(vault, amountOut);
        }

        IRouter(router).pluginIncreasePosition(order.account, order.collateralToken, order.indexToken, order.sizeDelta, order.isLong);

        // pay executor
        _transferOutETH(order.executionFee, _feeReceiver);

        emit ExecuteIncreaseOrder(
            order.account,
            _orderIndex,
            order.purchaseToken,
            order.purchaseTokenAmount,
            order.collateralToken,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee,
            currentPrice
        );
    }

    function createDecreaseOrder(
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        address _receiveToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold,
        uint256 _minOut,
        bool _withdrawETH
    ) external payable nonReentrant {

        _transferInETH();
        
        require(msg.value > minExecutionFee, "OB: insufficient execution fee");
        if (_withdrawETH) {
            if(_receiveToken != address(0))
                require(_receiveToken == weth, "OB: invalid _receiveToken");
            else   
                require(_collateralToken == weth, "OB: invalid _collateralToken");  
        }

        

        _createDecreaseOrder(msg.sender, _collateralToken,_receiveToken, _collateralDelta, _indexToken, _sizeDelta, _isLong, _triggerPrice, _triggerAboveThreshold, _minOut, _withdrawETH);
    }

    function _createDecreaseOrder(
        address _account,
        address _collateralToken,
        address _receiveToken,
        uint256 _collateralDelta,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold,
        uint256 _minOut,
        bool _withdrawETH
    ) private {
        uint256 _orderIndex = decreaseOrdersIndex[_account];
        DecreaseOrder memory order = DecreaseOrder(
            _account,
            _collateralToken,
            _receiveToken,
            _collateralDelta,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            _minOut,
            _withdrawETH,
            msg.value
        );
        decreaseOrdersIndex[_account] = _orderIndex.add(1);
        decreaseOrders[_account][_orderIndex] = order;
        _addToOpenOrders(_account,_orderIndex,OrderType.DECREASE);

        emit CreateDecreaseOrder(_account, _orderIndex, _collateralToken, _receiveToken, _collateralDelta, _indexToken, _sizeDelta, _isLong, _triggerPrice, _triggerAboveThreshold, msg.value);

    }

    function executeDecreaseOrder(
        address _address,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external override nonReentrant {
        _onlyOrderExecutor();
        DecreaseOrder memory order = decreaseOrders[_address][_orderIndex];
        require(order.account != address(0), "OB: non-existent order");

        // decrease long should use min price
        // decrease short should use max price
        (uint256 currentPrice, ) = validatePositionOrderPrice(order.triggerAboveThreshold, order.triggerPrice, order.indexToken, !order.isLong, true);

        delete decreaseOrders[_address][_orderIndex];
        _removeFromOpenOrders(_address,_orderIndex,OrderType.DECREASE);

        uint256 amountOut = IRouter(router).pluginDecreasePosition(
            order.account,
            order.collateralToken,
            order.indexToken,
            order.collateralDelta,
            order.sizeDelta,
            order.isLong,
            address(this)
        );

        if (order.receiveToken != address(0)) {
            IERC20(order.collateralToken).safeTransfer(vault, amountOut);
            amountOut = _vaultSwap(order.collateralToken, order.receiveToken, order.minOut, address(this));
        }

        if (order.withdrawETH) {
            _transferOutETHWithGasLimit(amountOut, payable(order.account));
        } else {
            if (order.receiveToken != address(0)) {
                IERC20(order.receiveToken).safeTransfer(order.account, amountOut);
            }else{
                IERC20(order.collateralToken).safeTransfer(order.account, amountOut);
            }    
        }

        _transferOutETH(order.executionFee, _feeReceiver);

        emit ExecuteDecreaseOrder(
            order.account,
            _orderIndex,
            order.collateralToken,
            order.collateralDelta,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee,
            currentPrice
        );
    }

    function cancelDecreaseOrder(uint256 _orderIndex) public nonReentrant {
        DecreaseOrder memory order = decreaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OB: non-existent order");

        delete decreaseOrders[msg.sender][_orderIndex];
        _removeFromOpenOrders(msg.sender,_orderIndex,OrderType.DECREASE);
        _transferOutETH(order.executionFee, msg.sender);

        emit CancelDecreaseOrder(
            order.account,
            _orderIndex,
            order.collateralToken,
            order.collateralDelta,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee
        );
    }

    function updateDecreaseOrder(
        uint256 _orderIndex,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external nonReentrant {
        DecreaseOrder storage order = decreaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OB: non-existent order");

        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        order.sizeDelta = _sizeDelta;
        order.collateralDelta = _collateralDelta;

        emit UpdateDecreaseOrder(
            msg.sender,
            _orderIndex,
            order.collateralToken,
            _collateralDelta,
            order.indexToken,
            _sizeDelta,
            order.isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }

    function _transferInETH() private {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    function _transferOutETH(uint256 _amountOut, address payable _receiver) private {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }
    function _transferOutETHWithGasLimit(uint256 _amountOut, address payable _receiver) internal {
        IWETH(weth).withdraw(_amountOut);
        _receiver.transfer(_amountOut);
    }

    function _swap(
        address[] memory _path,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        if (_path.length == 2) {
            return _vaultSwap(_path[0], _path[1], _minOut, _receiver);
        }
        if (_path.length == 3) {
            uint256 midOut = _vaultSwap(_path[0], _path[1], 0, address(this));
            IERC20(_path[1]).safeTransfer(vault, midOut);
            return _vaultSwap(_path[1], _path[2], _minOut, _receiver);
        }

        revert("OB: invalid _path.length");
    }

    function _vaultSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        uint256 amountOut;

        // if (_tokenOut == usdm) {
        //     // buyUSDM
        //     amountOut = IVault(vault).buyUSDM(_tokenIn, _receiver);
        // } else if (_tokenIn == usdm) {
        //     // sellUSDM
        //     amountOut = IVault(vault).sellUSDM(_tokenOut, _receiver);
        // } else {
            // swap
            amountOut = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);
        // }

        require(amountOut >= _minOut, "OB: insufficient amountOut");
        return amountOut;
    }

   function getShouldExecuteOrderList(bool _returnFirst
    ) external override view returns (bool ,uint160[] memory) {
        if(!chainlinkOrderExecutionActive){
            return(false,new uint160[](0));
        }

        uint256 orderListSize = orderList.size;
        uint160[] memory shouldExecuteOrders = new uint160[](orderListSize*3);
        uint256 shouldExecuteIndex = 0;

        if(orderListSize>0){

            for (
                uint i = orderList.iterate_start();
                orderList.iterate_valid(i);
                i = orderList.iterate_next(i)
            ) {
                (, Orders memory order) = orderList.iterate_get(i);
                bool shouldExecute =false;

                if (order.orderType == OrderType.SWAP){
                    SwapOrder memory swapOrder = swapOrders[order.account][order.orderIndex];
                    shouldExecute = !validateSwapOrderPriceWithTriggerAboveThreshold(swapOrder.path, swapOrder.triggerRatio);
                }
                else if (order.orderType == OrderType.INCREASE){
                    IncreaseOrder memory increaseOrder = increaseOrders[order.account][order.orderIndex];
                    (, shouldExecute ) = validatePositionOrderPrice(increaseOrder.triggerAboveThreshold, increaseOrder.triggerPrice, increaseOrder.indexToken, increaseOrder.isLong, false);
                }else if (order.orderType == OrderType.DECREASE){
                    DecreaseOrder memory decreaseOrder = decreaseOrders[order.account][order.orderIndex];
                    (uint256 size, , , , , , , ) = IVault(vault).getPosition(decreaseOrder.account, decreaseOrder.collateralToken, decreaseOrder.indexToken, decreaseOrder.isLong);
                    if(size>0){
                        (, shouldExecute ) = validatePositionOrderPrice(decreaseOrder.triggerAboveThreshold, decreaseOrder.triggerPrice, decreaseOrder.indexToken, !decreaseOrder.isLong, false);
                    }    
                }
                if (shouldExecute){
                    if(_returnFirst){
                        return(true,new uint160[](0));
                    }
                    shouldExecuteOrders[shouldExecuteIndex*3] = uint160(order.account);
                    shouldExecuteOrders[shouldExecuteIndex*3+1] = uint160(order.orderIndex);
                    shouldExecuteOrders[shouldExecuteIndex*3+2] = uint160(order.orderType);
                    shouldExecuteIndex++;
                }                
            }
        }

        uint160[] memory returnList = new uint160[](shouldExecuteIndex*3); 

        for (uint256 i = 0; i < shouldExecuteIndex*3; i++) {
            returnList[i]=shouldExecuteOrders[i];
        }
        
        return (shouldExecuteIndex>0,returnList);
    }


}
