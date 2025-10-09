// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../factory/Factory.sol";

/**
 * @title Pool
 * @dev A constant product AMM pool contract for DEX functionality
 * @notice This contract implements a Uniswap V2-style AMM with additional owner exit liquidity functionality
 */
contract Pool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // Events
    event ExitLiquidity(address indexed owner, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserve0, uint256 reserve1);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    // State variables
    address public factory;
    address public token0;
    address public token1;
    bool public initialized;

    // Timelock for sensitive operations (e.g., exitLiquidity)
    uint256 public constant EXIT_TIMELOCK = 1 days;
    uint256 public exitRequestTimestamp;

    uint256 private reserve0;
    uint256 private reserve1;
    uint32 private blockTimestampLast;

    // Anti-flash-loan / price impact controls
    // Max percentage of reserves allowed to be taken out per swap, in basis points (10000 = 100%)
    uint256 public maxSwapOutPercentBps = 10000;
    // Minimum reserves that must remain after a swap, per token
    uint256 public minLiquidityThreshold;

    // Optional sanity guard for sync: max allowed reserve drift per call (in BPS). 10000 disables checks.
    uint256 public maxSyncDriftBps = 10000;

    constructor() Ownable(msg.sender) {
        factory = msg.sender;
    }

    /**
     * @dev Initialize the pool with token addresses
     * @param _token0 First token address
     * @param _token1 Second token address
     */
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "Pool: not factory");
        require(!initialized, "Pool: initialized");
        require(_token0 != _token1, "Pool: identical");
        token0 = _token0 < _token1 ? _token0 : _token1;
        token1 = _token0 < _token1 ? _token1 : _token0;
        initialized = true;
    }

    /**
     * @dev Get the current reserves
     * @return _reserve0 Reserve of token0
     * @return _reserve1 Reserve of token1
     * @return _blockTimestampLast Last block timestamp
     */
    function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /**
     * @dev Update reserves
     * @param balance0 Balance of token0
     * @param balance1 Balance of token1
     */
    function _update(uint256 balance0, uint256 balance1) private {
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        reserve0 = balance0;
        reserve1 = balance1;
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    /**
     * @dev Exit liquidity function for owner - allows owner to withdraw all liquidity
     * @notice This function can only be called by the owner and will withdraw all tokens from the pool
     * @param to Address to receive the withdrawn tokens
     */
    function exitLiquidity(address to) external onlyOwner nonReentrant {
        require(to != address(0), "Pool: zero address");
        require(initialized, "Pool: not initialized");
        require(exitRequestTimestamp != 0, "Pool: exit not requested");
        require(block.timestamp >= exitRequestTimestamp + EXIT_TIMELOCK, "Pool: timelock active");
        
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        
        require(balance0 > 0 || balance1 > 0, "Pool: no liquidity to exit");
        
        // Transfer all tokens to the specified address
        if (balance0 > 0) {
            IERC20(token0).safeTransfer(to, balance0);
        }
        if (balance1 > 0) {
            IERC20(token1).safeTransfer(to, balance1);
        }
        
        // Update reserves to zero
        _update(0, 0);
        // Reset exit request timestamp
        exitRequestTimestamp = 0;
        
        emit ExitLiquidity(msg.sender, balance0, balance1);
    }


    /**
     * @dev Initiate an exit request to start the timelock countdown.
     */
    function requestExitLiquidity() external onlyOwner {
        require(initialized, "Pool: not initialized");
        exitRequestTimestamp = block.timestamp;
    }

    /**
     * @dev Cancel a previously requested exit.
     */
    function cancelExitLiquidity() external onlyOwner {
        exitRequestTimestamp = 0;
    }


    /**
     * @dev Transfer ownership to a new owner (only factory can call this)
     * @notice This allows the factory to transfer ownership to users who add liquidity
     * @param newOwner Address of the new owner
     */
    function transferOwnershipToUser(address newOwner) external {
        require(msg.sender == factory, "Pool: only factory can transfer ownership");
        require(newOwner != address(0), "Pool: new owner is zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Safe transfer function
     * @param token Token address
     * @param to Recipient address
     * @param value Amount to transfer
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        IERC20(token).safeTransfer(to, value);
    }

    /**
     * @dev Sync reserves with actual balances
     */
    function sync() external {
        // Restrict who can trigger sync to trusted actors
        address router = Factory(factory).trustedRouter();
        require(router != address(0), "Pool: router not set");
        require(msg.sender == factory || msg.sender == router || msg.sender == owner(), "Pool: unauthorized sync");

        uint256 newBal0 = IERC20(token0).balanceOf(address(this));
        uint256 newBal1 = IERC20(token1).balanceOf(address(this));

        if (maxSyncDriftBps < 10000) {
            if (reserve0 > 0) {
                uint256 min0 = (reserve0 * (10000 - maxSyncDriftBps)) / 10000;
                uint256 max0 = (reserve0 * (10000 + maxSyncDriftBps)) / 10000;
                require(newBal0 >= min0 && newBal0 <= max0, "Pool: sync drift0");
            }
            if (reserve1 > 0) {
                uint256 min1 = (reserve1 * (10000 - maxSyncDriftBps)) / 10000;
                uint256 max1 = (reserve1 * (10000 + maxSyncDriftBps)) / 10000;
                require(newBal1 >= min1 && newBal1 <= max1, "Pool: sync drift1");
            }
        }

        _update(newBal0, newBal1);
    }

    // ============ SWAP FUNCTIONS ============

    /**
     * @dev Swap tokens using constant product formula
     * @param amount0Out Amount of token0 to output
     * @param amount1Out Amount of token1 to output
     * @param to Address to receive output tokens
     * @param data Additional data (unused in this implementation)
     */
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "Pool: insufficient output amount");
        require(amount0Out < reserve0 && amount1Out < reserve1, "Pool: insufficient liquidity");
        require(to != token0 && to != token1, "Pool: invalid to");

        // Enforce per-swap output limits relative to current reserves if configured (<100%)
        if (maxSwapOutPercentBps < 10000) {
            if (amount0Out > 0) {
                require(amount0Out <= (reserve0 * maxSwapOutPercentBps) / 10000, "Pool: amount0Out too large");
            }
            if (amount1Out > 0) {
                require(amount1Out <= (reserve1 * maxSwapOutPercentBps) / 10000, "Pool: amount1Out too large");
            }
        }

        // Enforce minimum reserves remaining after swap if configured
        if (minLiquidityThreshold > 0) {
            require(reserve0 - amount0Out >= minLiquidityThreshold, "Pool: low reserve0 after swap");
            require(reserve1 - amount1Out >= minLiquidityThreshold, "Pool: low reserve1 after swap");
        }

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;

        require(amount0In > 0 || amount1In > 0, "Pool: insufficient input amount");
        require(amount0In <= balance0 && amount1In <= balance1, "Pool: insufficient balance");

        // Check K constraint (constant product)
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3; // 0.3% fee
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
        require(balance0Adjusted * balance1Adjusted >= uint256(reserve0) * reserve1 * 1000**2, "Pool: K");

        _update(balance0, balance1);

        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /**
     * @dev Configure per-swap maximum output percentage in basis points (10000 = 100%).
     */
    function setMaxSwapOutPercentBps(uint256 newBps) external onlyOwner {
        require(newBps > 0 && newBps <= 10000, "Pool: invalid bps");
        maxSwapOutPercentBps = newBps;
    }

    /**
     * @dev Configure minimum reserve threshold that must remain after swaps.
     */
    function setMinLiquidityThreshold(uint256 newMin) external onlyOwner {
        minLiquidityThreshold = newMin;
    }

    /**
     * @dev Configure max allowed reserve drift on sync (in BPS). 10000 disables checks.
     */
    function setMaxSyncDriftBps(uint256 newBps) external onlyOwner {
        require(newBps <= 10000, "Pool: invalid bps");
        maxSyncDriftBps = newBps;
    }

    /**
     * @dev Get the amount out for a given amount in
     * @param amountIn Amount of input tokens
     * @param reserveIn Reserve of input token
     * @param reserveOut Reserve of output token
     * @return amountOut Amount of output tokens
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "Pool: insufficient input amount");
        require(reserveIn > 0 && reserveOut > 0, "Pool: insufficient liquidity");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @dev Get the amount in for a given amount out
     * @param amountOut Amount of output tokens
     * @param reserveIn Reserve of input token
     * @param reserveOut Reserve of output token
     * @return amountIn Amount of input tokens
     */
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountIn) {
        require(amountOut > 0, "Pool: insufficient output amount");
        require(reserveIn > 0 && reserveOut > 0, "Pool: insufficient liquidity");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }
}