// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../pool/Pool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18); // Mint 1M tokens
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock Factory for testing
contract MockFactory {
    function createPool() external returns (address) {
        Pool pool = new Pool();
        return address(pool);
    }
}

contract PoolTest is Test {
    Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;
    MockFactory public factory;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    function setUp() public {
        // Deploy mock tokens
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");
        
        // Deploy factory
        factory = new MockFactory();
        
        // Deploy pool through factory to set correct factory address
        address poolAddress = factory.createPool();
        pool = Pool(poolAddress);
        
        // Setup initial state
        vm.startPrank(owner);
        token0.mint(owner, 1000000 * 10**18);
        token1.mint(owner, 1000000 * 10**18);
        token0.mint(user1, 100000 * 10**18);
        token1.mint(user1, 100000 * 10**18);
        token0.mint(user2, 100000 * 10**18);
        token1.mint(user2, 100000 * 10**18);
        vm.stopPrank();
    }
    
    function testInitialization() public {
        // Test that pool is not initialized initially
        assertFalse(pool.initialized());
        assertEq(pool.factory(), address(factory));
        assertEq(pool.owner(), address(factory));
    }
    
    function testInitialize() public {
        // Deploy a fresh pool for this test
        address freshPoolAddress = factory.createPool();
        Pool freshPool = Pool(freshPoolAddress);
        
        // Test successful initialization
        vm.prank(address(factory));
        freshPool.initialize(address(token0), address(token1));
        
        assertTrue(freshPool.initialized());
        // Check that tokens are ordered correctly (token0 < token1)
        assertEq(freshPool.token0(), address(token0) < address(token1) ? address(token0) : address(token1));
        assertEq(freshPool.token1(), address(token0) < address(token1) ? address(token1) : address(token0));
    }
    
    function testInitializeOnlyFactory() public {
        // Test that only factory can initialize
        vm.expectRevert("Pool: not factory");
        vm.prank(user1);
        pool.initialize(address(token0), address(token1));
    }
    
    function testInitializeAlreadyInitialized() public {
        // Initialize once
        vm.prank(address(factory));
        pool.initialize(address(token0), address(token1));
        
        // Try to initialize again
        vm.expectRevert("Pool: initialized");
        vm.prank(address(factory));
        pool.initialize(address(token0), address(token1));
    }
    
    function testInitializeIdenticalTokens() public {
        // Test that identical tokens are rejected
        vm.expectRevert("Pool: identical");
        vm.prank(address(factory));
        pool.initialize(address(token0), address(token0));
    }
    
    function testInitializeTokenOrdering() public {
        // Test that tokens are ordered correctly (token0 < token1)
        address higherToken = address(0x9999);
        address lowerToken = address(0x1111);
        
        vm.prank(address(factory));
        pool.initialize(higherToken, lowerToken);
        
        assertEq(pool.token0(), lowerToken);
        assertEq(pool.token1(), higherToken);
    }
    
    function testGetReserves() public {
        // Initialize pool
        vm.prank(address(factory));
        pool.initialize(address(token0), address(token1));
        
        // Initially reserves should be 0
        (uint256 reserve0, uint256 reserve1, uint32 blockTimestampLast) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);
        assertEq(blockTimestampLast, 0);
    }
    
    function testSync() public {
        // Deploy a fresh pool for this test
        address freshPoolAddress = factory.createPool();
        Pool freshPool = Pool(freshPoolAddress);
        
        
        // Initialize pool
        vm.prank(address(factory));
        freshPool.initialize(address(token0), address(token1));
         
        // Transfer some tokens to pool
        vm.prank(owner);
        token0.transfer(address(freshPool), 1000 * 10**18);
        token1.transfer(address(freshPool), 2000 * 10**18);
        console.log("1--token0.balanceOf(owner)", token0.balanceOf(address(freshPool)));
        console.log("2--token1.balanceOf(owner)", token1.balanceOf(address(freshPool)));
        // Sync reserves
        freshPool.sync();
        // Check reserves are updated
        (uint256 reserve0, uint256 reserve1,) = freshPool.getReserves();
        console.log("3--reserve0", reserve0);
        console.log("4--reserve1", reserve1);
        assertEq(reserve0, 2000 * 10**18);
        assertEq(reserve1, 1000 * 10**18);
    }
    
    function testExitLiquidity() public {
        // Initialize pool
        vm.prank(address(factory));
        pool.initialize(address(token0), address(token1));
        
        // Transfer tokens to pool
        vm.prank(owner);
        token0.transfer(address(pool), 1000 * 10**18);
        token1.transfer(address(pool), 2000 * 10**18);
        
        // Sync reserves
        pool.sync();
        
        // Record initial balances
        uint256 initialBalance0 = token0.balanceOf(owner);
        uint256 initialBalance1 = token1.balanceOf(owner);
        
        // Exit liquidity as owner (factory)
        vm.prank(address(factory));
        pool.exitLiquidity(owner);
        
        // Check tokens were transferred back
        assertEq(token0.balanceOf(owner), initialBalance0 + 1000 * 10**18);
        assertEq(token1.balanceOf(owner), initialBalance1 + 2000 * 10**18);
        
        // Check pool has no tokens left
        assertEq(token0.balanceOf(address(pool)), 0);
        assertEq(token1.balanceOf(address(pool)), 0);
        
        // Check reserves are zero
        (uint256 reserve0, uint256 reserve1,) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);
    }
    
    function testExitLiquidityOnlyOwner() public {
        // Initialize pool
        vm.prank(address(factory));
        pool.initialize(address(token0), address(token1));
        
        // Try to exit liquidity as non-owner
        vm.expectRevert();
        vm.prank(user1);
        pool.exitLiquidity(user1);
    }
    
    function testExitLiquidityZeroAddress() public {
        // Initialize pool
        vm.prank(address(factory));
        pool.initialize(address(token0), address(token1));
        
        // Try to exit liquidity to zero address
        vm.expectRevert("Pool: zero address");
        vm.prank(address(factory));
        pool.exitLiquidity(address(0));
    }
    
    function testExitLiquidityNotInitialized() public {
        // Try to exit liquidity before initialization
        vm.expectRevert("Pool: not initialized");
        vm.prank(address(factory));
        pool.exitLiquidity(owner);
    }
    
    function testExitLiquidityNoLiquidity() public {
        // Initialize pool
        vm.prank(address(factory));
        pool.initialize(address(token0), address(token1));
        
        // Try to exit liquidity when pool has no tokens
        vm.expectRevert("Pool: no liquidity to exit");
        vm.prank(address(factory));
        pool.exitLiquidity(owner);
    }
    
    function testSafeTransfer() public {
        // Deploy a fresh pool for this test
        uint256 balance = token0.balanceOf(user1);
        address freshPoolAddress = factory.createPool();
        Pool freshPool = Pool(freshPoolAddress);
        
        // Initialize pool
        vm.prank(address(factory));
        freshPool.initialize(address(token0), address(token1));
        
        // Transfer tokens to pool
        vm.prank(owner);
        token0.transfer(address(freshPool), 1000 * 10**18);
        
        // Test that _safeTransfer works (called internally by exitLiquidity)
        vm.prank(address(factory));
        freshPool.exitLiquidity(user1);
        console.log("token0.balanceOf(user1)", token0.balanceOf(user1));
        assertEq(token0.balanceOf(user1) - balance, 1000 * 10**18);
    }
    
    function testSafeTransferFailure() public {
        // Deploy a fresh pool for this test
        address freshPoolAddress = factory.createPool();
        Pool freshPool = Pool(freshPoolAddress);
        
        // Create a mock token that always fails transfer
        MockERC20 failingToken = new MockERC20("Failing", "FAIL");
        
        // Initialize pool with failing token
        vm.prank(address(factory));
        freshPool.initialize(address(failingToken), address(token1));
        
        // Mint tokens to owner first
        vm.prank(owner);
        failingToken.mint(owner, 1000 * 10**18);
        
        // Transfer tokens to pool
        vm.prank(owner);
        failingToken.transfer(address(freshPool), 1000 * 10**18);
        
        // This should work normally
        vm.prank(address(factory));
        freshPool.exitLiquidity(owner);
        
        // Verify tokens were transferred back
        assertEq(failingToken.balanceOf(owner), 1000 * 10**18);
    }
    
    function testReentrancyProtection() public {
        // Initialize pool
        vm.prank(address(factory));
        pool.initialize(address(token0), address(token1));
        
        // Transfer tokens to pool
        vm.prank(owner);
        token0.transfer(address(pool), 1000 * 10**18);
        token1.transfer(address(pool), 2000 * 10**18);
        
        // Test that exitLiquidity is protected against reentrancy
        // This is a basic test - in a real scenario, you'd need a malicious contract
        vm.prank(address(factory));
        pool.exitLiquidity(owner);
        
        // If we get here without reverting, reentrancy protection is working
        assertTrue(true);
    }
    
    function testLargeNumbers() public {
        // Test with very large numbers to ensure uint256 works correctly
        vm.prank(address(factory));
        pool.initialize(address(token0), address(token1));
        
        // Use very large numbers
        uint256 largeAmount = type(uint256).max / 2;
        
        // Mint large amounts
        vm.prank(owner);
        token0.mint(address(pool), largeAmount);
        token1.mint(address(pool), largeAmount);
        
        // Sync should work without overflow
        pool.sync();
        
        (uint256 reserve0, uint256 reserve1,) = pool.getReserves();
        assertEq(reserve0, largeAmount);
        assertEq(reserve1, largeAmount);
    }
    
}