// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFactoryR {
    function getPair(address, address) external view returns (address);
    function swapFeeBps() external view returns (uint16);
    function lpFeeBps() external view returns (uint16);
    function protocolFeeBps() external view returns (uint16);
    function protocolFeeVault() external view returns (address);
}
interface IPairR {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112, uint112, uint32);
    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to) external;
}
interface IWPHRS {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
    function approve(address, uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
}
interface ISwapVaultN {
    function notifyDeposit(address token) external;
}
library SafeTransferR {
    function safeTransfer(address token, address to, uint value) internal {
        (bool s, bytes memory d) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(s && (d.length == 0 || abi.decode(d, (bool))), "TRANSFER_FAIL");
    }
    function safeTransferFrom(address token, address from, address to, uint value) internal {
        (bool s, bytes memory d) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(s && (d.length == 0 || abi.decode(d, (bool))), "TRANSFER_FROM_FAIL");
    }
}

contract Router {
    using SafeTransferR for address;

    address public factory;
    address public immutable wphrs;

    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "OWN"); _; }

    event FactoryUpdated(address indexed oldFactory, address indexed newFactory);
    event OwnerUpdated(address indexed newOwner);

    modifier ensure(uint deadline) { require(block.timestamp <= deadline, "EXPIRED"); _; }

    constructor(address _factory, address _wphrs) {
        require(_factory != address(0) && _wphrs != address(0), "ZERO");
        owner = msg.sender;
        factory = _factory;
        wphrs = _wphrs;
    }

    function setOwner(address n) external onlyOwner {
        require(n != address(0), "ZERO");
        owner = n;
        emit OwnerUpdated(n);
    }

    function setFactory(address newFactory) external onlyOwner {
        require(newFactory != address(0), "ZERO");
        address old = factory;
        factory = newFactory;
        emit FactoryUpdated(old, newFactory);
    }

    function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired) external returns (uint liquidity) {
        address pair = _pairFor(tokenA, tokenB);
        tokenA.safeTransferFrom(msg.sender, pair, amountADesired);
        tokenB.safeTransferFrom(msg.sender, pair, amountBDesired);
        liquidity = IPairR(pair).mint(msg.sender);
    }

    function addLiquidityPHRS(address token, uint amountTokenDesired) external payable returns (uint liquidity) {
        IWPHRS(wphrs).deposit{value: msg.value}();
        address pair = _pairFor(token, wphrs);
        token.safeTransferFrom(msg.sender, pair, amountTokenDesired);
        address(wphrs).safeTransfer(pair, msg.value);
        liquidity = IPairR(pair).mint(msg.sender);
    }

	function removeLiquidity(address tokenA, address tokenB, uint liquidity) external returns (uint amountA, uint amountB) {
		address pair = _pairFor(tokenA, tokenB);
		address(pair).safeTransferFrom(msg.sender, pair, liquidity);
		(uint a0, uint a1) = IPairR(pair).burn(msg.sender);
		(address t0, ) = _sortTokens(tokenA, tokenB);
		(amountA, amountB) = tokenA == t0 ? (a0, a1) : (a1, a0);
	}

    function removeLiquidityPHRS(address token, uint liquidity) external returns (uint amountToken, uint amountPHRS) {
        address pair = _pairFor(token, wphrs);
        address(pair).safeTransferFrom(msg.sender, pair, liquidity);
        (uint a0, uint a1) = IPairR(pair).burn(address(this));
        (address t0, ) = _sortTokens(token, wphrs);
        (uint amtToken, uint amtW) = token == t0 ? (a0, a1) : (a1, a0);
        token.safeTransfer(msg.sender, amtToken);
        IWPHRS(wphrs).withdraw(amtW);
        (bool ok, ) = msg.sender.call{value: amtW}("");
        require(ok, "SEND_PHRS");
        return (amtToken, amtW);
    }

    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external ensure(deadline) returns (uint amountOut) {
        require(path.length >= 2, "PATH");
        address inToken = path[0];
        (uint proto, uint toPair, address vault) = _splitProtocol(inToken, amountIn);
        if (proto > 0) {
            require(vault != address(0), "NO_VAULT");
            inToken.safeTransferFrom(msg.sender, vault, proto);
            _tryNotify(vault, inToken);
        }
        inToken.safeTransferFrom(msg.sender, _pairFor(path[0], path[1]), toPair);
        amountOut = _swap(path, to);
        require(amountOut >= amountOutMin, "SLIPPAGE");
    }

    function swapExactPHRSForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable ensure(deadline) returns (uint amountOut) {
        require(path.length >= 2 && path[0] == wphrs, "PATH");
        IWPHRS(wphrs).deposit{value: msg.value}();
        (uint proto, uint toPair, address vault) = _splitProtocol(wphrs, msg.value);
        if (proto > 0) {
            require(vault != address(0), "NO_VAULT");
            address(wphrs).safeTransfer(vault, proto);
            _tryNotify(vault, wphrs);
        }
        address(wphrs).safeTransfer(_pairFor(path[0], path[1]), toPair);
        amountOut = _swap(path, to);
        require(amountOut >= amountOutMin, "SLIPPAGE");
    }

    function swapExactTokensForPHRS(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external ensure(deadline) returns (uint amountOut) {
        require(path.length >= 2 && path[path.length - 1] == wphrs, "PATH");
        address inToken = path[0];
        (uint proto, uint toPair, address vault) = _splitProtocol(inToken, amountIn);
        if (proto > 0) {
            require(vault != address(0), "NO_VAULT");
            inToken.safeTransferFrom(msg.sender, vault, proto);
            _tryNotify(vault, inToken);
        }
        inToken.safeTransferFrom(msg.sender, _pairFor(path[0], path[1]), toPair);
        amountOut = _swap(path, address(this));
        IWPHRS(wphrs).withdraw(amountOut);
        (bool ok, ) = to.call{value: amountOut}("");
        require(ok, "SEND_PHRS");
        require(amountOut >= amountOutMin, "SLIPPAGE");
    }

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint amountOut) {
        require(path.length >= 2, "PATH");
        uint amt = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint rIn, uint rOut) = _reserves(path[i], path[i+1]);
            uint16 fee = IFactoryR(factory).lpFeeBps();
            uint amtAfter = amt * (10_000 - fee) / 10_000;
            amt = (amtAfter * rOut) / (rIn + amtAfter);
        }
        return amt;
    }

    function _swap(address[] calldata path, address to) internal returns (uint amountOut) {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i+1]);
            address pair = _pairFor(input, output);
            (address t0, ) = _sortTokens(input, output);
            (uint rIn, uint rOut) = _reserves(input, output);
            uint16 fee = IFactoryR(factory).lpFeeBps();
            uint balIn = _balance(input, pair);
            uint amountIn = balIn - rIn;
            uint amountInAfterFee = amountIn * (10_000 - fee) / 10_000;
            uint out = (amountInAfterFee * rOut) / (rIn + amountInAfterFee);
            (uint amount0Out, uint amount1Out) = input == t0 ? (uint(0), out) : (out, uint(0));
            address nextTo = i < path.length - 2 ? _pairFor(output, path[i+2]) : to;
            IPairR(pair).swap(amount0Out, amount1Out, nextTo);
            amountOut = out;
        }
    }

    function _pairFor(address a, address b) internal view returns (address) {
        address p = IFactoryR(factory).getPair(a, b);
        require(p != address(0), "NO_PAIR");
        return p;
    }

    function _reserves(address a, address b) internal view returns (uint rIn, uint rOut) {
        address pair = _pairFor(a, b);
        (address t0, ) = _sortTokens(a, b);
        (uint112 r0, uint112 r1,) = IPairR(pair).getReserves();
        (rIn, rOut) = a == t0 ? (r0, r1) : (r1, r0);
    }

    function _sortTokens(address a, address b) internal pure returns (address, address) {
        require(a != b, "IDENTICAL");
        return a < b ? (a, b) : (b, a);
    }

    function _balance(address token, address who) internal view returns (uint) {
        (bool s, bytes memory d) = token.staticcall(abi.encodeWithSelector(0x70a08231, who));
        require(s && d.length >= 32, "BAL_FAIL");
        return abi.decode(d, (uint));
    }

    function _splitProtocol(address /*inToken*/, uint amountIn) internal view returns (uint proto, uint toPair, address vault) {
        uint16 p = IFactoryR(factory).protocolFeeBps();
        vault = IFactoryR(factory).protocolFeeVault();
        proto = (amountIn * p) / 10_000;
        toPair = amountIn - proto;
    }

	function _tryNotify(address vault, address token) internal {
		if (vault == address(0)) return;
		vault.call(abi.encodeWithSelector(ISwapVaultN.notifyDeposit.selector, token));
	}

    receive() external payable { require(msg.sender == wphrs, "NOT_WPHRS"); }
}
