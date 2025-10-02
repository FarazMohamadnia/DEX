// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Pool
 * @dev A constant product AMM pool contract for DEX functionality
 * @notice This contract implements a Uniswap V2-style AMM with additional owner exit liquidity functionality
 */
contract Pool is Ownable, ReentrancyGuard {
    // Events
    event ExitLiquidity(address indexed owner, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserve0, uint256 reserve1);

    // State variables
    address public factory;
    address public token0;
    address public token1;
    bool public initialized;

    uint256 private reserve0;
    uint256 private reserve1;
    uint32 private blockTimestampLast;

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
        
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        
        require(balance0 > 0 || balance1 > 0, "Pool: no liquidity to exit");
        
        // Transfer all tokens to the specified address
        if (balance0 > 0) {
            _safeTransfer(token0, to, balance0);
        }
        if (balance1 > 0) {
            _safeTransfer(token1, to, balance1);
        }
        
        // Update reserves to zero
        _update(0, 0);
        
        emit ExitLiquidity(msg.sender, balance0, balance1);
    }

    /**
     * @dev Safe transfer function
     * @param token Token address
     * @param to Recipient address
     * @param value Amount to transfer
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: TRANSFER_FAILED');
    }

    /**
     * @dev Sync reserves with actual balances
     */
    function sync() external {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }
}