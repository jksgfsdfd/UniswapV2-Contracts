// SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

import "./Interfaces/IFactory.sol";
import "./Interfaces/IPair.sol";
import "./Libraries/UQ112x112.sol";
import "./Interfaces/IERC20.sol";
import "./Interfaces/IWETH.sol";
import "./Libraries/TransferHelper.sol";

contract RouterV2 {
    using UQ112x112 for uint224;

    address public immutable factory;

    address public immutable WETH;

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    // helpful since the core contract doesn't return dust tokens when adding liquidity and requires atomic transfer of tokens and minting of lp tokens

    function getTransferDetails(
        // in uniswap this function is named _addLiquidity and doesn't return the pair address
        address tokenA,
        address tokenB,
        uint112 amountADesired,
        uint112 amountBDesired,
        uint112 amountAMin,
        uint112 amountBMin
    ) internal returns (address pair, uint amountA, uint amountB) {
        // get ratio of the tokens in the pool and then add the transfer the tokens accordingly before calling the mint function
        if (
            (pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB)) ==
            address(0)
        ) {
            pair = IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint112 reserve0, uint112 reserve1, ) = IPair(pair).getReserves();

        if (reserve0 == 0 && reserve1 == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint amountBOptimal = (reserve1 * amountADesired) / reserve0;
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Price of B is too low");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint amountAOptimal = (reserve0 * amountBDesired) / reserve1;
                require(
                    amountAOptimal <= amountADesired &&
                        amountAOptimal >= amountAMin,
                    "Out of price range"
                );
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint112 amountADesired,
        uint112 amountBDesired,
        uint112 amountAMin,
        uint112 amountBMin
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        address pair;
        (pair, amountA, amountB) = getTransferDetails(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IPair(pair).mint(msg.sender);
    }

    // allowing users to provide ETH for liquidity
    function addLiquidityETH(
        address token,
        uint112 amountTokenDesired,
        uint112 amountTokenMin,
        uint112 amountETHMin
    )
        external
        payable
        returns (uint amountToken, uint amountETH, uint liquidity)
    {
        address pair;
        (pair, amountToken, amountETH) = getTransferDetails(
            token,
            WETH,
            amountTokenDesired,
            uint112(msg.value),
            amountTokenMin,
            amountETHMin
        );
        IWETH(WETH).deposit{value: amountETH}();
        IWETH(WETH).transfer(pair, amountETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        liquidity = IPair(pair).mint(msg.sender);

        // returning dust eth
        if (amountETH < msg.value) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to
    ) public returns (uint amountA, uint amountB) {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "No such pair");
        IPair(pair).transferFrom(msg.sender, pair, liquidity);
        (uint amount0, uint amount1) = IPair(pair).burn(to);
        (amountA, amountB) = tokenA < tokenB
            ? (amount0, amount1)
            : (amount1, amount0);
        require(
            amountA >= amountAMin && amountB >= amountBMin,
            "Not enough tokens received"
        );
    }

    // to retreive eth, the router will act as middleman and receive the weth tokens which it will convert and then send eth to the receiver
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to
    ) external returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this)
        );
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransfer(token, to, amountToken);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // the above methods to remove liquidity requires the owner to interact with the core contract to setup allowance for this router contract. this can be avoided by using the permit functionality
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint112 amountAMin,
        uint112 amountBMin,
        address to,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountA, uint amountB) {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "No such pair");
        IPair(pair).permit(
            msg.sender,
            address(this),
            liquidity,
            deadline,
            v,
            r,
            s
        );
        (amountA, amountB) = removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            to
        );
    }

    // in functions which removes liquidity and has ETH as one token, this router contract acts as the middleman and the amount of the other tokens transferred to the caller is amountB ie. the amount that was sent by the liquidity pool contract. But for tokens which have a fee on transfer the amount of tokens that this router contract will receive will be less. Hence we will have to use balanceOf(this) to send the tokenss to the caller.
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to
    ) public returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this)
        );
        IWETH(WETH).withdraw(amountETH);
        amountToken = IERC20(token).balanceOf(address(this));
        TransferHelper.safeTransfer(token, to, amountToken);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHSupportingFeeOnTransferTokensWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address to
    ) external returns (uint amountToken, uint amountETH) {
        address pair = IUniswapV2Factory(factory).getPair(token, WETH);
        require(pair != address(0), "No such pair");
        IPair(pair).permit(
            msg.sender,
            address(this),
            liquidity,
            deadline,
            v,
            r,
            s
        );
        (
            amountToken,
            amountETH
        ) = removeLiquidityETHSupportingFeeOnTransferTokens(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            to
        );
    }
}
