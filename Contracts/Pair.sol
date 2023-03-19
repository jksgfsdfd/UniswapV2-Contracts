// SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

import "./PairERC20.sol";
import "./Interfaces/IERC20.sol";
import "./Interfaces/IFactory.sol";
import "./Libraries/Math.sol";
import "./Libraries/UQ112x112.sol";
import "./Interfaces/IUniswapV2Callee.sol";

contract Pair is PairERC20 {
    using UQ112x112 for uint224;

    address public factory;
    address public token0;
    address public token1;

    // accessing all these together results in a single sload operation.
    // the cumulative price is calculated using the cached reserves after the last transaciton of the previous block as using the ERC20 balance is manipulatable
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // the last liquidity at which the protocol fee was calculated

    uint public constant MINIMUM_LIQUIDITY = 10 ** 3;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(
        address indexed sender,
        uint amount0,
        uint amount1,
        address indexed to
    );
    event Sync(uint112 balance0, uint112 balance1);
    event Swap(
        address swapper,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address to
    );

    constructor(address _token0, address _token1) {
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function update(
        uint balance0,
        uint balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) internal {
        require(
            balance0 <= type(uint112).max && balance1 <= type(uint112).max,
            "Overflow... use skim()"
        );
        // update cumulative price if this is the first transaction of this block
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint _blockTimestampLast = blockTimestampLast;
        if (_blockTimestampLast < blockTimestamp) {
            uint timeElapsed = blockTimestamp - _blockTimestampLast;
            price0CumulativeLast +=
                uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) *
                timeElapsed;
            price1CumulativeLast +=
                uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) *
                timeElapsed;
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        // will we save gas if we use balance0 and balance1 instead?
        emit Sync(reserve0, reserve1);
    }

    function mintFee(uint _reserve0, uint _reserve1) internal returns (bool) {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        if (feeTo == address(0)) {
            return false;
        }
        uint rootK = Math.sqrt(_reserve0 * _reserve1);
        uint rootKLast = Math.sqrt(kLast);
        if (rootKLast != 0) {
            uint numerator = totalSupply * (rootK - rootKLast);
            uint denominator = rootK * 5 + rootKLast;
            uint mintAmount = numerator / denominator;
            _mint(feeTo, mintAmount);
        }
        return true;
    }

    // we will consider the amount added as the difference between the current balance and the cached reserves.
    function mint(address to) external returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        bool feeOn = mintFee(_reserve0, _reserve1);
        // this method of calculating the amounts in means that we will have to take care of ensuring that the correct amounts are passed.
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0In = balance0 - _reserve0;
        uint amount1In = balance1 - _reserve1;
        uint _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            // if liquidity is below MINIMUM_Liquidity, it reverts
            liquidity = Math.sqrt(amount0In * amount1In) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                (amount1In * _totalSupply) / _reserve1,
                (amount0In * _totalSupply) / _reserve0
            );
            require(liquidity>0,"Insufficient amount added");
            _mint(to, liquidity);
        }

        _reserve0 = uint112(balance0);
        _reserve1 = uint112(balance1);
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        if (feeOn) {
            kLast = _reserve0 * _reserve1;
        }
        // the amounts which was actually considered for liquidity would be different if the ratio was not exact
        emit Mint(to, amount0In, amount1In);
    }

    function burn(address to) external returns (uint amount0, uint amount1) {
        // the amount of liquidity tokens to burn is found by the number of liquidity tokens that is deposited in this contracts balance
        uint liquidity = balanceOf[address(this)];
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        bool feeOn = mintFee(_reserve0, _reserve1);
        // transfer amount of tokens corresponding to the burn amount of liquidity toknes
        amount0 = (_reserve0 * liquidity) / totalSupply;
        amount1 = (_reserve1 * liquidity) / totalSupply;
        _burn(address(this), liquidity);
        IERC20(token0).transfer(to, amount0);
        IERC20(token1).transfer(to, amount1);
        _reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        _reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        if (feeOn) {
            kLast = _reserve0 * _reserve1;
        }
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external {
        // transferring the tokens first and checking the payments next allows for flash swaps
        address _token0 = token0;
        address _token1 = token1;
        IERC20(_token0).transfer(to, amount0Out);
        IERC20(_token1).transfer(to, amount1Out);
        if (data.length > 0) {
            IUniswapV2Callee(to).uniswapV2Call(
                msg.sender,
                amount0Out,
                amount1Out,
                data
            );
        }

        uint112 _reserve0 = reserve0;
        uint112 _reserve1 = reserve1;
        uint initialLiquidity = _reserve0 * _reserve1;
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;
        uint adjustedBalance0 = 1000 * balance0 - 3 * amount0In;
        uint adjustedBalance1 = 1000 * balance1 - 3 * amount1In;
        require(
            adjustedBalance0 * adjustedBalance1 >= 10 ** 6 * initialLiquidity,
            "Not enough tokens transferred"
        );
        update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // used to sync the reserves with the balance
    function sync() external {
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        update(balance0, balance1, reserve0, reserve1);
    }

    // used to match the balance with the reserves. this is useful if the balance of either tokens goes past max(uint112)
    function skim(address to) external {
        address _token0 = token0;
        address _token1 = token1;
        uint amount0Extra = IERC20(_token0).balanceOf(address(this)) - reserve0;
        uint amount1Extra = IERC20(_token1).balanceOf(address(this)) - reserve1;
        IERC20(_token0).transfer(to, amount0Extra);
        IERC20(_token0).transfer(to, amount1Extra);
    }
}
