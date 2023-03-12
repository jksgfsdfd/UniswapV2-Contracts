// SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

import "./Interfaces/IFactory.sol";
import "./Interfaces/IPair.sol";
import "./Libraries/UQ112x112.sol";
import "./Interfaces/IERC20.sol";

contract RouterV2 {
    using UQ112x112 for uint224;

    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint112 amountADesired,
        uint112 amountBDesired,
        uint112 amountAMin,
        uint112 amountBMin
    ) external {
        // get ratio of the tokens in the pool and then add the transfer the tokens accordingly before calling the mint function
        address pair;
        if (
            (pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB)) ==
            address(0)
        ) {
            pair = IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint112 reserve0, uint112 reserve1, ) = IPair(pair).getReserves();

        uint transferA;
        uint transferB;
        if (reserve0 == 0 && reserve1 == 0) {
            transferA = amountADesired;
            transferB = amountBDesired;
        } else {
            uint amountBOptimal = (reserve1 * amountADesired) / reserve0;
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Price of B is too low");
                transferA = amountADesired;
                transferB = amountBOptimal;
            } else {
                uint amountAOptimal = (reserve0 * amountBDesired) / reserve1;
                require(
                    amountAOptimal <= amountADesired &&
                        amountAOptimal >= amountAMin,
                    "Out of price range"
                );
                transferA = amountAOptimal;
                transferB = amountBDesired;
            }
        }
        IERC20(tokenA).transferFrom(msg.sender, pair, transferA);
        IERC20(tokenB).transferFrom(msg.sender, pair, transferB);
        IPair(pair).mint(msg.sender);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidty,
        uint amountAMin,
        uint amountBMin,
        address to
    ) external returns (uint amountA, uint amountB) {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "No such pair");
        IPair(pair).transferFrom(msg.sender, pair, liquidty);
        (uint amount0, uint amount1) = IPair(pair).burn(to);
        (amountA, amountB) = tokenA < tokenB
            ? (amount0, amount1)
            : (amount1, amount0);
        require(
            amountA >= amountAMin && amountB >= amountBMin,
            "Not enough tokens received"
        );
    }
}
