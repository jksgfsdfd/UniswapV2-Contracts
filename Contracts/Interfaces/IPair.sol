pragma solidity >=0.5.0;

interface IPair {
    function getReserves() external view returns (uint112, uint112, uint32);

    function mint(address to) external returns (uint liquidity);

    function transferFrom(
        address from,
        address to,
        uint amount
    ) external returns (bool);

    function burn(address to) external returns (uint amount0, uint amount1);

    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;
}
