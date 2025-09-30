# BETA
# Technical Documentation for Decentralized Exchange (DEX) Smart Contracts

**Date**: September 27, 2025  
**Purpose**: To provide a technical and executable specification for smart contracts of a DEX based on an AMM model (similar to Uniswap V3), supporting token swaps, liquidity management, governance, oracle integration, and staking rewards.  
**Blockchain**: Ethereum or EVM-compatible (e.g., BSC).  
**Tools**: Solidity (^0.8.0), Hardhat, OpenZeppelin, Chainlink.  

## 1. Overall Architecture  
- **Core Contracts**: Factory and Pool for managing pools and core operations.  
- **Periphery Contracts**: Router and Position Manager for user-friendly interactions.  
- **Additional Contracts**: Governance (for DAO), Oracle (for pricing), Staking (for rewards).  
- **Model**: AMM with Concentrated Liquidity (like Uniswap V3) for higher capital efficiency.  
- **Standards**: ERC-20 (tokens), ERC-721 (liquidity positions), Proxy Pattern for upgradability.  

---

## 2. Factory Contract  
**Description**: Creates and manages liquidity pools for token pairs. Includes ownership for updates.  

### Key Functions  
- **createPool**  
  - **Parameters**: address tokenA, address tokenB, uint24 fee  
  - **Returns**: address pool  
  - **Visibility**: external  
  - **Description**: Creates a new pool for a token pair with a specified fee (e.g., 0.3%). Reverts if the pool already exists.  
  - **Sample Code**:  
    ```solidity
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {
        require(tokenA != tokenB, "Tokens must be different");
        // Compute pool address and deploy
    }
    ```

- **setOwner**  
  - **Parameters**: address _owner  
  - **Returns**: none  
  - **Visibility**: external  
  - **Description**: Changes the factory owner. Callable only by the current owner.  

- **enableFeeAmount**  
  - **Parameters**: uint24 fee, int24 tickSpacing  
  - **Returns**: none  
  - **Visibility**: public  
  - **Description**: Enables a new fee level with specified tick spacing.  

- **getPool**  
  - **Parameters**: address tokenA, address tokenB, uint24 fee  
  - **Returns**: address  
  - **Visibility**: public view  
  - **Description**: Returns the address of an existing pool.  

---

## 3. Pool Contract  
**Description**: Manages liquidity, swaps, and price oracles for a specific token pair. Uses the x * y = k formula or Concentrated Liquidity.  

### Key Functions  
- **swap**  
  - **Parameters**: address recipient, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96, bytes calldata data  
  - **Returns**: int256 amount0, int256 amount1  
  - **Visibility**: external  
  - **Description**: Executes a token swap. amountSpecified is positive for exact input, negative for exact output.  

- **mint**  
  - **Parameters**: address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data  
  - **Returns**: uint256 amount0, uint256 amount1  
  - **Visibility**: external  
  - **Description**: Adds liquidity in a specified tick range. Issues LP tokens as NFTs.  

- **burn**  
  - **Parameters**: int24 tickLower, int24 tickUpper, uint128 amount  
  - **Returns**: uint256 amount0, uint256 amount1  
  - **Visibility**: external  
  - **Description**: Removes liquidity and burns LP tokens.  

- **collect**  
  - **Parameters**: address recipient, int24 tickLower, int24 tickUpper, uint128 amount0Requested, uint128 amount1Requested  
  - **Returns**: uint128 amount0, uint128 amount1  
  - **Visibility**: external  
  - **Description**: Collects accumulated fees.  

- **observe**  
  - **Parameters**: uint32[] calldata secondsAgos  
  - **Returns**: int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s  
  - **Visibility**: external view  
  - **Description**: Returns TWAP data for price oracle.  

- **increaseObservationCardinalityNext**  
  - **Parameters**: uint16 observationCardinalityNext  
  - **Returns**: none  
  - **Visibility**: external  
  - **Description**: Increases oracle capacity for more data storage.  

---

## 4. Router Contract  
**Description**: Facilitates complex swaps and liquidity management. Users interact with pools via this contract.  

### Key Functions  
- **exactInputSingle**  
  - **Parameters**: struct ExactInputSingleParams {address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96}  
  - **Returns**: uint256 amountOut  
  - **Visibility**: external payable  
  - **Description**: Single-hop exact input swap.  

- **exactInput**  
  - **Parameters**: struct ExactInputParams {bytes path, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum}  
  - **Returns**: uint256 amountOut  
  - **Visibility**: external payable  
  - **Description**: Multi-hop exact input swap.  

- **exactOutputSingle**  
  - **Parameters**: struct ExactOutputSingleParams {address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 deadline, uint256 amountOut, uint256 amountInMaximum, uint160 sqrtPriceLimitX96}  
  - **Returns**: uint256 amountIn  
  - **Visibility**: external payable  
  - **Description**: Single-hop exact output swap.  

- **exactOutput**  
  - **Parameters**: struct ExactOutputParams {bytes path, address recipient, uint256 deadline, uint256 amountOut, uint256 amountInMaximum}  
  - **Returns**: uint256 amountIn  
  - **Visibility**: external payable  
  - **Description**: Multi-hop exact output swap.  

- **uniswapV3SwapCallback**  
  - **Parameters**: int256 amount0Delta, int256 amount1Delta, bytes calldata data  
  - **Returns**: none  
  - **Visibility**: external  
  - **Description**: Callback for post-swap payment.  

---

## 5. Position Manager Contract  
**Description**: Manages liquidity positions as NFTs (ERC-721). Essential for V3-like functionality.  

### Key Functions  
- **positions**  
  - **Parameters**: uint256 tokenId  
  - **Returns**: uint96 nonce, address operator, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1  
  - **Visibility**: external view  
  - **Description**: Returns details of a liquidity position.  

- **mint**  
  - **Parameters**: struct MintParams {address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, address recipient, uint256 deadline}  
  - **Returns**: uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1  
  - **Visibility**: external payable  
  - **Description**: Creates a new position and issues an NFT.  

- **tokenURI**  
  - **Parameters**: uint256 tokenId  
  - **Returns**: string memory  
  - **Visibility**: public view  
  - **Description**: Returns metadata URI for the NFT.  

---

## 6. Governance Contract  
**Description**: Manages decentralized governance (DAO) using governance tokens (ERC-20).  

### Key Functions  
- **propose**  
  - **Parameters**: address[] targets, uint[] values, string[] signatures, bytes[] calldatas, string description  
  - **Returns**: uint proposalId  
  - **Visibility**: public  
  - **Description**: Creates a new proposal for protocol changes (e.g., fee updates).  

- **vote**  
  - **Parameters**: uint proposalId, bool support  
  - **Returns**: none  
  - **Visibility**: public  
  - **Description**: Votes with weight based on staked tokens.  

- **execute**  
  - **Parameters**: uint proposalId  
  - **Returns**: none  
  - **Visibility**: public  
  - **Description**: Executes a proposal after quorum and voting period.  

**Sample Code**:  
```solidity
contract Governance is Ownable {
    struct Proposal { /* Proposal details */ }
    function propose(address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) public returns (uint) {
        // Proposal logic
    }
}
```

---

## 7. Oracle Integration Contract  
**Description**: Integrates with Chainlink for real-time pricing to prevent manipulation.  

### Key Functions  
- **getLatestPrice**  
  - **Parameters**: address aggregator (e.g., Chainlink ETH/USD)  
  - **Returns**: int256 price  
  - **Visibility**: public view  
  - **Description**: Returns the latest price from the oracle.  

**Sample Code**:  
```solidity
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
contract Oracle {
    AggregatorV3Interface internal priceFeed;
    constructor(address _aggregator) {
        priceFeed = AggregatorV3Interface(_aggregator);
    }
    function getLatestPrice() public view returns (int) {
        (,int price,,,) = priceFeed.latestRoundData();
        return price;
    }
}
```

---

## 8. Staking/Farming Contract  
**Description**: Rewards liquidity providers for staking LP tokens.  

### Key Functions  
- **stake**  
  - **Parameters**: uint256 amount  
  - **Returns**: none  
  - **Visibility**: external  
  - **Description**: Stakes LP tokens and starts reward calculation.  

- **withdraw**  
  - **Parameters**: uint256 amount  
  - **Returns**: none  
  - **Visibility**: external  
  - **Description**: Withdraws stake and claims rewards.  

- **claimReward**  
  - **Parameters**: none  
  - **Returns**: uint256 reward  
  - **Visibility**: external  
  - **Description**: Claims accumulated rewards.  

**Sample Code**:  
```solidity
contract Staking {
    mapping(address => uint) public balances;
    function stake(uint256 amount) external {
        // Transfer tokens and update balance
    }
}
```

---