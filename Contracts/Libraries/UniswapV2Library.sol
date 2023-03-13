//SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

import "../Interfaces/IFactory.sol";
import "../Interfaces/IPair.sol";

library UniswapV2Library {
    function getAmountOut(
        uint amount0In,
        uint reserve0,
        uint reserve1
    ) internal pure returns (uint amountOut) {
        amountOut =
            (reserve0 * reserve1 * 1000) /
            (reserve0 * 1000 + 997 * amount0In);
    }

    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (uint reserveA, uint reserveB) {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "Invalid pair");
        (uint reserve0, uint reserve1, ) = IPair(pair).getReserves();
        (reserveA, reserveB) = tokenA < tokenB
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    function getAmountsOut(
        address factory,
        address[] calldata path,
        uint amountIn
    ) internal view returns (uint[] memory amountsOut) {
        require(path.length > 1, "Invalid Path");
        address tokenIn = path[0];
        amountsOut = new uint[](path.length);
        amountsOut[0] = amountIn;
        for (uint i = 1; i < path.length; i++) {
            address tokenOut = path[i];
            (uint reserveTokenIn, uint reserveTokenOut) = getReserves(
                factory,
                tokenIn,
                tokenOut
            );
            amountIn = getAmountOut(amountIn, reserveTokenIn, reserveTokenOut);
            amountsOut[i] = amountIn;
        }
    }

    function getAmountIn(
        uint amount0Out,
        uint reserve0,
        uint reserve1
    ) internal pure returns (uint amount1In) {
        amount1In =
            ((1000 * reserve0 * reserve1) / (997 * (reserve0 - amount0Out))) -
            1000 *
            reserve1;
    }

    function getAmountsIn(
        address factory,
        address[] calldata path,
        uint amountOut
    ) internal view returns (uint[] memory amountsIn) {
        require(path.length > 1, "Invalid Path");
        amountsIn = new uint[](path.length);
        amountsIn[path.length - 1] = amountOut;
        for (uint i = path.length - 1; i >= 1; i--) {
            address tokenIn = path[i - 1];
            address tokenOut = path[i];
            address pair = IUniswapV2Factory(factory).getPair(
                tokenIn,
                tokenOut
            );
            require(pair != address(0), "Invalid Path");
            (uint reserveTokenIn, uint reserveTokenOut) = getReserves(
                factory,
                tokenIn,
                tokenOut
            );
            amountOut = getAmountIn(amountOut, reserveTokenOut, reserveTokenIn);
            amountsIn[i - 1] = amountOut;
        }
    }
}
