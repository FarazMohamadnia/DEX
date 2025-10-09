// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../factory/Factory.sol";
import "../pool/Pool.sol";

/**
 * @title Router
 * @dev Router contract for DEX functionality
 * @notice Provides high-level functions for swapping tokens and managing liquidity
 */
contract Router is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    // Factory contract address
    address public immutable factory;
    
    // WETH address (for ETH handling)
    address public immutable WETH;
    
    // Events
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    
    event AddLiquidity(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );
    
    event RemoveLiquidity(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        address indexed to
    );

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Router: expired");
        _;
    }

    constructor(address _factory, address _WETH) Ownable(msg.sender) {
        factory = _factory;
        WETH = _WETH;
    }

    // ============ SWAP FUNCTIONS ============

    /**
     * @dev Swap exact tokens for tokens
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of output tokens
     * @param path Array of token addresses (tokenA, tokenB)
     * @param to Address to receive output tokens
     * @param deadline Transaction deadline
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: insufficient output amount");
        
        _safeTransferFrom(path[0], msg.sender, _getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    /**
     * @dev Swap tokens for exact tokens
     * @param amountOut Amount of output tokens
     * @param amountInMax Maximum amount of input tokens
     * @param path Array of token addresses
     * @param to Address to receive output tokens
     * @param deadline Transaction deadline
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, "Router: excessive input amount");
        
        _safeTransferFrom(path[0], msg.sender, _getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    /**
     * @dev Swap exact ETH for tokens
     * @param amountOutMin Minimum amount of output tokens
     * @param path Array of token addresses (WETH, tokenB)
     * @param to Address to receive output tokens
     * @param deadline Transaction deadline
     */
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WETH, "Router: invalid path");
        amounts = getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: insufficient output amount");
        
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(_getPair(path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    /**
     * @dev Swap tokens for exact ETH
     * @param amountOut Amount of ETH to receive
     * @param amountInMax Maximum amount of input tokens
     * @param path Array of token addresses (tokenA, WETH)
     * @param to Address to receive ETH
     * @param deadline Transaction deadline
     */
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "Router: invalid path");
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, "Router: excessive input amount");
        
        _safeTransferFrom(path[0], msg.sender, _getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        _safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // ============ LIQUIDITY FUNCTIONS ============

    /**
     * @dev Add liquidity to a pool by transferring tokens directly
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param amountA Amount of tokenA to transfer
     * @param amountB Amount of tokenB to transfer
     * @param to Address to receive ownership (usually msg.sender)
     * @param deadline Transaction deadline
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountAUsed, uint256 amountBUsed) {
        address pair = _getPair(tokenA, tokenB);
        require(pair != address(0), "Router: pair does not exist");
        
        _safeTransferFrom(tokenA, msg.sender, pair, amountA);
        _safeTransferFrom(tokenB, msg.sender, pair, amountB);
        
        // Transfer ownership to the user who added liquidity
        Factory(factory).transferPoolOwnership(tokenA, tokenB, to);
        
        // Sync the pool reserves
        Pool(pair).sync();
        
        emit AddLiquidity(tokenA, tokenB, amountA, amountB, 0);
        return (amountA, amountB);
    }

    /**
     * @dev Add liquidity with optimal amounts calculated automatically
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param amountADesired Desired amount of tokenA
     * @param amountBDesired Desired amount of tokenB
     * @param amountAMin Minimum amount of tokenA
     * @param amountBMin Minimum amount of tokenB
     * @param to Address to receive ownership (usually msg.sender)
     * @param deadline Transaction deadline
     */
    function addLiquidityOptimal(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = _getPair(tokenA, tokenB);
        require(pair != address(0), "Router: pair does not exist");
        
        (uint256 reserveA, uint256 reserveB) = _getReserves(tokenA, tokenB);
        
        if (reserveA == 0 && reserveB == 0) {
            // First liquidity provision - use desired amounts
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            // Calculate optimal amounts based on current reserves
            uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Router: insufficient amountB");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                require(amountAOptimal <= amountADesired && amountAOptimal >= amountAMin, "Router: insufficient amountA");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }
        
        _safeTransferFrom(tokenA, msg.sender, pair, amountA);
        _safeTransferFrom(tokenB, msg.sender, pair, amountB);
        
        // Transfer ownership to the user who added liquidity
        Factory(factory).transferPoolOwnership(tokenA, tokenB, to);
        
        // Sync the pool reserves
        Pool(pair).sync();
        
        emit AddLiquidity(tokenA, tokenB, amountA, amountB, 0);
    }

    /**
     * @dev Remove liquidity from a pool (only pool owner can call exitLiquidity)
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param to Address to receive tokens
     * @param deadline Transaction deadline
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = _getPair(tokenA, tokenB);
        require(pair != address(0), "Router: pair does not exist");
        
        // Get current balances before exit
        (uint256 reserveA, uint256 reserveB) = _getReserves(tokenA, tokenB);
        
        // Temporarily transfer ownership to this router, call exitLiquidity, then transfer back
        address currentOwner = Pool(pair).owner();
        Factory(factory).transferPoolOwnership(tokenA, tokenB, address(this));
        Pool(pair).exitLiquidity(to);
        Factory(factory).transferPoolOwnership(tokenA, tokenB, currentOwner);
        
        emit RemoveLiquidity(tokenA, tokenB, reserveA, reserveB, to);
        return (reserveA, reserveB);
    }

    // ============ QUOTE FUNCTIONS ============

    /**
     * @dev Get amounts out for a given amount in
     * @param amountIn Amount of input tokens
     * @param path Array of token addresses
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        public
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Router: invalid path");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i], path[i + 1]);
            amounts[i + 1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /**
     * @dev Get amounts in for a given amount out
     * @param amountOut Amount of output tokens
     * @param path Array of token addresses
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        public
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Router: invalid path");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i - 1], path[i]);
            amounts[i - 1] = _getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    /**
     * @dev Quote function for calculating optimal amounts
     * @param amountA Amount of tokenA
     * @param reserveA Reserve of tokenA
     * @param reserveB Reserve of tokenB
     */
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        returns (uint256 amountB)
    {
        return _quote(amountA, reserveA, reserveB);
    }

    // ============ INTERNAL FUNCTIONS ============

    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? _getPair(output, path[i + 2]) : _to;
            Pool(_getPair(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function _getPair(address tokenA, address tokenB) internal view returns (address) {
        return Factory(factory).getPair(tokenA, tokenB);
    }

    function _getReserves(address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = _sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = Pool(_getPair(tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "Router: identical addresses");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        internal
        pure
        returns (uint256 amountB)
    {
        require(amountA > 0, "Router: insufficient amount");
        require(reserveA > 0 && reserveB > 0, "Router: insufficient liquidity");
        amountB = (amountA * reserveB) / reserveA;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "Router: insufficient input amount");
        require(reserveIn > 0 && reserveOut > 0, "Router: insufficient liquidity");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "Router: insufficient output amount");
        require(reserveIn > 0 && reserveOut > 0, "Router: insufficient liquidity");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        IERC20(token).safeTransferFrom(from, to, value);
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "Router: ETH transfer failed");
    }

    // ============ FALLBACK FUNCTIONS ============

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }
}

// WETH interface for ETH handling
interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}