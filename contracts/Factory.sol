// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Pair.sol";

interface IPairInit { function initialize(address token0, address token1) external; }
interface IPairMeta { function token0() external view returns (address); function token1() external view returns (address); }

contract Factory {
    address public owner;
    address public protocolFeeVault;
    uint16 public swapFeeBps = 10;
    uint16 public lpFeeBps = 8;
    uint16 public protocolFeeBps = 2;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    struct FeeOverride { bool enabled; uint16 swapFeeBps; uint16 lpFeeBps; uint16 protocolFeeBps; }
    mapping(address => FeeOverride) public pairFeeOverride;

    event OwnerUpdated(address indexed newOwner);
    event ProtocolVaultUpdated(address indexed newVault);
    event FeesUpdated(uint16 swapFeeBps, uint16 lpFeeBps, uint16 protocolFeeBps);
    event PairCreated(address indexed token0, address indexed token1, address pair, uint index);
    event PairFeeOverride(address indexed pair, bool enabled, uint16 swapFeeBps, uint16 lpFeeBps, uint16 protocolFeeBps);

    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }

    constructor() { owner = msg.sender; }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    function setProtocolFeeVault(address vault) external onlyOwner {
        protocolFeeVault = vault;
        emit ProtocolVaultUpdated(vault);
    }

    function setFees(uint16 _swap, uint16 _lp, uint16 _proto) external onlyOwner {
        require(_swap == _lp + _proto, "split mismatch");
        require(_swap <= 100, "max 1.00%");
        swapFeeBps = _swap;
        lpFeeBps = _lp;
        protocolFeeBps = _proto;
        emit FeesUpdated(_swap, _lp, _proto);
    }

    function setPairFeeOverride(address pair, bool enabled, uint16 _swap, uint16 _lp, uint16 _proto) external onlyOwner {
        if (enabled) {
            require(_swap == _lp + _proto, "split mismatch");
            require(_swap <= 100, "max 1.00%");
        }
        pairFeeOverride[pair] = FeeOverride(enabled, _swap, _lp, _proto);
        emit PairFeeOverride(pair, enabled, _swap, _lp, _proto);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "identical");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "zero");
        require(getPair[token0][token1] == address(0), "exists");

        bytes memory bytecode = type(Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
            if iszero(pair) { revert(0,0) }
        }
        IPairInit(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length - 1);
    }

    function allPairsLength() external view returns (uint) { return allPairs.length; }

    function getPairs(uint start, uint count) external view returns (address[] memory out) {
        uint n = allPairs.length;
        if (start >= n) return new address[](0);
        uint end = start + count;
        if (end > n) end = n;
        uint len = end - start;
        out = new address[](len);
        for (uint i; i < len; i++) {
            out[i] = allPairs[start + i];
        }
    }

    function getPairsWithTokens(uint start, uint count)
        external
        view
        returns (address[] memory pairs, address[] memory t0s, address[] memory t1s)
    {
        uint n = allPairs.length;
		if (start >= n) {
            return (new address[](0), new address[](0), new address[](0));
        }
        uint end = start + count;
        if (end > n) end = n;
        uint len = end - start;

        pairs = new address[](len);
        t0s = new address[](len);
        t1s = new address[](len);

        for (uint i; i < len; i++) {
            address p = allPairs[start + i];
            pairs[i] = p;
            t0s[i] = IPairMeta(p).token0();
            t1s[i] = IPairMeta(p).token1();
        }
    }
}
