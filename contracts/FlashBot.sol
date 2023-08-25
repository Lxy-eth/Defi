//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import 'hardhat/console.sol';


import "./interfaces/IWETH.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IFlashBot.sol";
import "./libraries/Decimal.sol";

contract FlashBot is Ownable , IFlashBot {
    using Decimal for Decimal.D256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet  baseTokens;

    address immutable WETH;

    address permissioned;

    event  WithDrawn(address indexed token, uint256 indexed amount);
    event  BaseTokenAdd(address indexed token);
    event BaseTokenRemoved(address indexed token);

    constructor(address _WETH) {
        WETH = _WETH;
        baseTokens.add(_WETH);
    }

    receive() external payable {}

    fallback(bytes calldata _input) external payable returns (bytes memory){
        (address sender,uint256 amount0,uint256 amount1,bytes memory data) = abi.decode(_input,(address,uint256,uint256,bytes));
        uniswapV2Call(sender,amount0,amount1,data);
    }


    function withdraw() external {
        uint256 balance = address(this).balance;
        if(balance > 0){
           payable(owner()).transfer(balance);
         emit WithDrawn(owner(),balance);
        }

        for (uint256 i = 0;i < baseTokens.length();i++){
            IERC20 token = IERC20(baseTokens.at(i));
            balance = token.balanceOf(address(this));
            if(balance > 0){
                token.safeTransfer(owner(),balance); 
            }
        }
    }


    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) public {
        require(msg.sender == permissioned,"FlashBot: Only owner can call");
        require(sender == address(this),"FlashBot: Only this contract can call");
        
        uint256 borrowedAmount = amount0 == 0 ? amount1 : amount0;
        CallbackData memory info  = abi.decode(data,(CallbackData));
        
        IERC20(info.debtToken).safeTransfer(info.debtPool,borrowedAmount);

        (uint256 amount0Out,uint256 amount1Out) = 
            info.debtTokenSmaller ? (uint256(0),borrowedAmount) : (borrowedAmount,uint256(0));

        IUniswapV2Pair(info.targetPool).swap(amount0Out, amount1Out, address(this), new bytes(0));

        IERC20(info.debtToken).safeTransfer(info.debtPool, info.debtAmount);
    }


    function addBaseToken(address token) external onlyOwner {
        baseTokens.add(token);
        emit BaseTokenAdd(token);
    }

    function removeBaseToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if(balance > 0){
            IERC20(token).safeTransfer(owner(),balance);
        }

        baseTokens.remove(token);
        emit BaseTokenRemoved(token);
    }

    function getBaseTokens() external view returns (address[] memory) {
        address[] memory tokens = new address[](baseTokens.length());
        for (uint256 i = 0;i < baseTokens.length();i++){
            tokens[i] = baseTokens.at(i);
        }
        return tokens;
    }

     function baseTokensContains(address token) public view returns (bool) {
        return baseTokens.contains(token);
    }

    function isbaseTokenSmaller(address pool0,address pool1) internal view returns (bool baseSmaller,address baseToken,address quoteToken){
        require(pool0 != pool1,"FlashBot: Same pool");
        (address pool0Token0,address pool0Token1) = (IUniswapV2Pair(pool0).token0(),IUniswapV2Pair(pool0).token1());
        (address pool1Token0,address pool1Token1) = (IUniswapV2Pair(pool1).token0(),IUniswapV2Pair(pool1).token1());
        require(pool0Token0 < pool0Token1 && pool1Token0 < pool1Token1, 'Non standard uniswap AMM pair');
        require(pool0Token0 == pool1Token0 && pool0Token1 == pool1Token1, 'Require same token pair');
        require(baseTokensContains(pool0Token0) || baseTokensContains(pool0Token1), 'No base token in pair');

        (baseSmaller,baseToken,quoteToken) = baseTokensContains(pool0Token0) ? (true,pool0Token0,pool0Token1) : (false,pool0Token1,pool0Token0);

    }

    function getOrderedReserves(
        address pool0,
        address pool1,
        bool baseSmaller
    ) internal 
      view
      returns (
        address lowerPool,
        address higherPool,
        OrderedReserves memory orderedReserves
        ) {
            (uint256 pool0Reserve0,uint256 pool0Reserve1,) = IUniswapV2Pair(pool0).getReserves();
            (uint256 pool1Reserve0,uint256 pool1Reserve1,) = IUniswapV2Pair(pool1).getReserves();

            (Decimal.D256 memory price0,Decimal.D256 memory price1) = 
                baseSmaller 
                    ? (Decimal.from(pool0Reserve1).div(pool0Reserve0),Decimal.from(pool1Reserve0).div(pool1Reserve1))
                    : (Decimal.from(pool0Reserve0).div(pool0Reserve1),Decimal.from(pool1Reserve1).div(pool1Reserve0));

            if (price0.lessThan(price1)) {
                (lowerPool, higherPool) = (pool0, pool1);
                (orderedReserves.tokenA1, orderedReserves.tokenB1, orderedReserves.tokenA2, orderedReserves.tokenB2) = baseSmaller 
                        ? (pool0Reserve0, pool0Reserve1, pool1Reserve0, pool1Reserve1)
                        : (pool0Reserve1, pool0Reserve0, pool1Reserve1, pool1Reserve0);
            }
            console.log('Borrow from pool:', lowerPool);
            console.log('Sell to pool:', higherPool);
        }

    function getFlash(address pool0,address pool1) external {
            ArbitrageInfo memory info;
            (info.baseTokenSmaller,info.baseToken,info.quoteToken) = isbaseTokenSmaller(pool0,pool1);
            OrderedReserves memory orderedReserves;
            (info.lowerPool,info.higherPool,orderedReserves) = getOrderedReserves(pool0,pool1,info.baseTokenSmaller);

            uint256 balanceBefore = IERC20(info.baseToken).balanceOf(address(this));
            permissioned = info.lowerPool;

        {
            uint256 borrowAmount = calcBorrowAmount(orderedReserves);
            (uint256 amountAOut,uint256 amountBOut) = info.baseTokenSmaller ? (uint256(0),borrowAmount) : (borrowAmount,0);

            uint256 debtAmount = getAmountIn(borrowAmount,orderedReserves.tokenA1,orderedReserves.tokenB1);
            uint256 baseTokenAmount = getAmountOut(borrowAmount,orderedReserves.tokenA2,orderedReserves.tokenB2);
            require(baseTokenAmount > debtAmount,"FlashBot: No profit");
            console.log('Profit:', (baseTokenAmount - debtAmount) / 1 ether);


            CallbackData memory callbackData;
            callbackData.debtPool = info.lowerPool;
            callbackData.targetPool = info.higherPool;
            callbackData.debtTokenSmaller = info.baseTokenSmaller;
            callbackData.borrowedToken = info.quoteToken;
            callbackData.debtToken = info.baseToken;
            callbackData.debtAmount = debtAmount;
            callbackData.debtTokenOutAmount = baseTokenAmount;

            bytes memory data = abi.encode(callbackData);
            IUniswapV2Pair(info.lowerPool).swap(amountAOut, amountBOut, address(this), data);
        }

        uint256 balanceAfter = IERC20(info.baseToken).balanceOf(address(this));
        require(balanceAfter > balanceBefore,"FlashBot: No profit");
        if(info.baseToken == WETH){
            IWETH(WETH).withdraw(balanceAfter - balanceBefore);
        }

        permissioned = address(0);

    }       


    function getProfit(
        address poo0,
        address pool1
    ) external 
      view 
      returns (
        uint256 profit,
        address baseToken
      ) {
        (bool baseTokenSmaller,,) = isbaseTokenSmaller(poo0,pool1);
        baseToken = baseTokenSmaller ? IUniswapV2Pair(poo0).token0() : IUniswapV2Pair(poo0).token1();

        (,,OrderedReserves memory orderedReserves) = getOrderedReserves(poo0,pool1,baseTokenSmaller);

        uint256 borrowAmount = calcBorrowAmount(orderedReserves);
        uint256 debtAmount = getAmountIn(borrowAmount,orderedReserves.tokenA1,orderedReserves.tokenB1);
        uint256 baseTokenAmount = getAmountOut(borrowAmount,orderedReserves.tokenA2,orderedReserves.tokenB2);

        if(debtAmount > baseTokenAmount){
            profit = 0;
        }else {
            profit = baseTokenAmount - debtAmount;
        }
      }


    function calcBorrowAmount(OrderedReserves memory reserves) internal pure returns (uint256 amount) {
        uint256 minA = reserves.tokenA1 < reserves.tokenA2 ? reserves.tokenA1 : reserves.tokenA2;
        uint256 minB = reserves.tokenB1 < reserves.tokenB2 ? reserves.tokenB1 : reserves.tokenB2;
        uint256 min = minA < minB ? minA : minB;

         uint256 d;
        if (min > 1e24) {
            d = 1e20;
        } else if (min > 1e23) {
            d = 1e19;
        } else if (min > 1e22) {
            d = 1e18;
        } else if (min > 1e21) {
            d = 1e17;
        } else if (min > 1e20) {
            d = 1e16;
        } else if (min > 1e19) {
            d = 1e15;
        } else if (min > 1e18) {
            d = 1e14;
        } else if (min > 1e17) {
            d = 1e13;
        } else if (min > 1e16) {
            d = 1e12;
        } else if (min > 1e15) {
            d = 1e11;
        } else {
            d = 1e10;
        }
        (int256 A1 ,int256 A2,int256 B1,int256 B2) = 
            (int256(reserves.tokenA1 / d),int256(reserves.tokenA2 / d),int256(reserves.tokenB1 / d),int256(reserves.tokenB2  / d));

        int256 a = A1*B1 - A2*B2;
        int256 b = 2 * B1 * B2 * (A1 + A2);
        int256 c = B1 * B2 *(A1*B2 - A2*B1);
        (int256 x1,int256 x2) = calcSolutionForQuadratic(a,b,c);
        require(x1 > 0 && x1 < B1 && x1 < B2 || (x2 > 0 && x2 < B1 && x2 < B2),"FlashBot: No solution");
        amount = (x1 > 0 && x1 < B1 && x1 < B2) ? uint256(x1) * d : uint256(x2) * d;
    }   


    function calcSolutionForQuadratic(int256 a,int256 b,int256 c) public pure returns (int256 x1,int256 x2) {
        int256 delta = b**2 - 4 * a * c;
        require(delta >= 0,"FlashBot: No solution");
        int256 sqrtDelta = int256(uint256(delta).sqrt());
        x1 = (-b + sqrtDelta) / (2 * a);
        x2 = (-b - sqrtDelta) / (2 * a);
    }


    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }
    

        function getAmountOut(
            uint amountIn, 
            uint reserveIn, 
            uint reserveOut
        ) public pure returns (uint amountOut) {
            require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
            require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
            uint amountInWithFee = amountIn.mul(997);
            uint numerator = amountInWithFee.mul(reserveOut);
            uint denominator = reserveIn.mul(1000).add(amountInWithFee);
            amountOut = numerator / denominator;
    }
}