// SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

contract PairERC20 {
    // standard erc20 with permit for metatransaction
    string public constant name = "UniswapV2";
    string public constant symbol = "UNI-V2";
    uint8 public constant decimals = 18;
    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    bytes32 public immutable DOMAIN_SEPERATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    mapping(address => mapping(address => uint)) public allowance;

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(
        address indexed approver,
        address indexed spender,
        uint value
    );

    constructor() {
        uint chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPERATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function _transfer(address from, address to, uint value) internal {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function transfer(address to, uint value) external returns (bool) {
        // in case of solidity versions where math is checked, it will automatically revert in case of underflow
        // require(balanceOf[msg.sender] >= value,"Not enough balance");
        _transfer(msg.sender, to, value);
        return true;
    }

    function _approve(address owner, address spender, uint value) internal {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function approve(address spender, uint value) public returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint value
    ) external returns (bool) {
        // uniswap doesn't subtract the value from allowance if it is max. Which means if it is set to max, then the approved users is able to access all the funds of the approver
        allowance[from][msg.sender] -= value;
        _transfer(from, to, value);
        return true;
    }

    function _mint(address to, uint value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        totalSupply -= value;
        balanceOf[from] -= value;
        emit Transfer(from, address(0), value);
    }

    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // enable off chain approval of assets
        require(deadline >= block.timestamp, "Expired pemit");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPERATOR,
                keccak256(
                    abi.encode(PERMIT_TYPEHASH, owner, spender, value, deadline)
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == owner,
            "invalid signature"
        );
        _approve(owner, spender, value);
    }
}
