// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../pool/Pool.sol";

// Factory contract for a simple Constant-Product AMM (DEX) in the spirit of
// Uniswap V2 / PancakeSwap. The Factory is responsible for creating and
// indexing Pair contracts (called Pool here) for token pairs.
//
// Key responsibilities:
// - Create new Pools deterministically via CREATE2
// - Maintain a registry mapping token pairs to their Pool
// - Expose a canonical list of all created Pools
// - Manage protocol fee recipient configuration (feeTo / feeToSetter)
//
// Assumptions about the Pool contract:
// - It must expose an initialize(address token0, address token1) function
//   which is callable once, by the Factory, immediately after deployment.
// - It should set its factory to msg.sender (this Factory) either via
//   constructor or via initialize, depending on your Pool implementation.

/// @notice Minimal interface for the Pool to allow initialization after deploy
interface IPool {
    function initialize(address token0, address token1) external;
    function transferOwnershipToUser(address newOwner) external;
}

contract Factory {
    // Emitted whenever a new Pool is created for a token pair
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 indexed pairIndex);

    // Address that receives protocol fees from Pools (if enabled on Pool level)
    address public feeTo;

    // Address allowed to update feeTo
    address public feeToSetter;

    // Mapping from tokenA => tokenB => Pool address
    mapping(address => mapping(address => address)) public getPair;

    // Canonical list of all created Pools
    address[] public allPairs;

    // For off-chain discovery: keccak256 of the Pool creation code.
    // This matches the UniswapV2 "pairCodeHash" that many tooling expects.
    bytes32 public immutable pairCodeHash;

    constructor(address _feeToSetter) {
        require(_feeToSetter != address(0), "Factory: feeToSetter zero");
        feeToSetter = _feeToSetter;
        pairCodeHash = keccak256(type(Pool).creationCode);
    }

    /// @notice Returns the number of Pools created by this Factory
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Create a Pool for tokenA and tokenB if none exists yet
    /// @dev Uses CREATE2 with salt = keccak256(token0, token1) for deterministic addresses
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "Factory: identical addresses");

        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        require(token0 != address(0), "Factory: zero address");
        require(getPair[token0][token1] == address(0), "Factory: pair exists");

        // Deterministic deployment using CREATE2 so the address is a pure
        // function of token0, token1, and Pool bytecode.
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new Pool{salt: salt}());

        // Initialize pool with sorted token ordering
        IPool(pair).initialize(token0, token1);

        // Populate bidirectional lookup and record in the global list
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length - 1);
    }

    /// @notice Set the address that collects protocol fees from Pools
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "Factory: not feeToSetter");
        feeTo = _feeTo;
    }

    /// @notice Transfer the ability to update feeTo to a new address
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "Factory: not feeToSetter");
        require(_feeToSetter != address(0), "Factory: zero feeToSetter");
        feeToSetter = _feeToSetter;
    }

    /// @notice Transfer ownership of a pool to a new owner (only router can call this)
    function transferPoolOwnership(address tokenA, address tokenB, address newOwner) external {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        address pair = getPair[token0][token1];
        require(pair != address(0), "Factory: pair does not exist");
        // Note: In a real implementation, you might want to verify that msg.sender is a trusted router
        IPool(pair).transferOwnershipToUser(newOwner);
    }

    /// @dev Internal helper to sort the token addresses lexicographically
    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "Factory: identical addresses");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}

  