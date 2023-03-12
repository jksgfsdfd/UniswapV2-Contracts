// SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

import "./Pair.sol";

contract Factory {
    // tokens are stored in sorted order
    mapping(address => mapping(address => address)) private pairs;

    // when feeTo is enabled, all pair contracts will start charging the protocol fee.
    address public feeTo;
    address public feeToSetter;

    address[] public allPairs;

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint
    );

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function getPair(
        address tokenA,
        address tokenB
    ) public view returns (address) {
        if (tokenA < tokenB) {
            return pairs[tokenA][tokenB];
        } else {
            return pairs[tokenB][tokenA];
        }
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address) {
        require(tokenA != tokenB, "Identical address");
        require(getPair(tokenA, tokenB) == address(0), "Pair already exists");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        address newPair = address(new Pair{salt: salt}(token0, token1));
        allPairs.push(newPair);
        emit PairCreated(token0, token1, newPair, allPairs.length);
        return newPair;
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "Not authorized");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "Not authorized");
        feeToSetter = _feeToSetter;
    }
}
