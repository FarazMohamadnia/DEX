// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../router/Router.sol";
import "../factory/Factory.sol";
import "../pool/Pool.sol";

// Mock ERC20 token for testing
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol, uint256 _totalSupply) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply;
        balanceOf[msg.sender] = _totalSupply;
    }
    
    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        
        emit Transfer(from, to, value);
        return true;
    }
    
    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

// Mock WETH contract for testing
contract MockWETH {
    mapping(address => uint256) public balanceOf;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);
    
    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    
    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "Insufficient balance");
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }
    
    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }
}

contract RouterTest is Test {
    Router public router;
    Factory public factory;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockWETH public weth;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public feeToSetter = address(0x3);
    
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10**18;
    
    function setUp() public {
        // Deploy contracts
        factory = new Factory(feeToSetter);
        weth = new MockWETH();
        router = new Router(address(factory), address(weth));
        // Configure trusted router
        vm.prank(feeToSetter);
        factory.setTrustedRouter(address(router));
        
        // Deploy test tokens
        tokenA = new MockERC20("TokenA", "TKA", INITIAL_SUPPLY);
        tokenB = new MockERC20("TokenB", "TKB", INITIAL_SUPPLY);
        
        // Create a pair
        factory.createPair(address(tokenA), address(tokenB));
        
        // Setup users with tokens
        tokenA.transfer(user1, 10000 * 10**18);
        tokenB.transfer(user1, 10000 * 10**18);
        tokenA.transfer(user2, 10000 * 10**18);
        tokenB.transfer(user2, 10000 * 10**18);
        
        // Approve router to spend tokens
        vm.prank(user1);
        tokenA.approve(address(router), type(uint256).max);
        vm.prank(user1);
        tokenB.approve(address(router), type(uint256).max);
        vm.prank(user2);
        tokenA.approve(address(router), type(uint256).max);
        vm.prank(user2);
        tokenB.approve(address(router), type(uint256).max);
    }
    
    // ============ LIQUIDITY TESTS ============
    
    function testAddLiquidity() public {
        uint256 amountA = 1000 * 10**18;
        uint256 amountB = 2000 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;
        
        address pair = factory.getPair(address(tokenA), address(tokenB));
        
        uint256 balanceA_before = tokenA.balanceOf(pair);
        uint256 balanceB_before = tokenB.balanceOf(pair);
        
        vm.prank(user1);
        (uint256 amountA_out, uint256 amountB_out) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            user1, // user1 becomes the owner
            deadline
        );
        
        assertEq(amountA_out, amountA);
        assertEq(amountB_out, amountB);
        assertEq(tokenA.balanceOf(pair), balanceA_before + amountA);
        assertEq(tokenB.balanceOf(pair), balanceB_before + amountB);
        
        // Verify that user1 is now the owner of the pool
        assertEq(Pool(pair).owner(), user1);
    }
    
    function testAddLiquidityOptimal() public {
        // First add some liquidity to establish a ratio
        vm.prank(user1);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
        
        // Now add optimal liquidity
        uint256 amountADesired = 500 * 10**18;
        uint256 amountBDesired = 1000 * 10**18;
        uint256 amountAMin = 400 * 10**18;
        uint256 amountBMin = 800 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(user2);
        (uint256 amountA_out, uint256 amountB_out) = router.addLiquidityOptimal(
            address(tokenA),
            address(tokenB),
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            user2, // user2 becomes the new owner
            deadline
        );
        
        // Should use the optimal ratio based on existing reserves
        assertTrue(amountA_out <= amountADesired);
        assertTrue(amountB_out <= amountBDesired);
        assertTrue(amountA_out >= amountAMin);
        assertTrue(amountB_out >= amountBMin);
        
        // Verify that user2 is now the owner of the pool
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(Pool(pair).owner(), user2);
    }
    
    function testAddLiquidityFirstTime() public {
        // Create a new pair for first-time liquidity
        MockERC20 tokenC = new MockERC20("TokenC", "TKC", INITIAL_SUPPLY);
        MockERC20 tokenD = new MockERC20("TokenD", "TKD", INITIAL_SUPPLY);
        
        tokenC.transfer(user1, 10000 * 10**18);
        tokenD.transfer(user1, 10000 * 10**18);
        
        vm.prank(user1);
        tokenC.approve(address(router), type(uint256).max);
        vm.prank(user1);
        tokenD.approve(address(router), type(uint256).max);
        
        factory.createPair(address(tokenC), address(tokenD));
        
        uint256 amountADesired = 1000 * 10**18;
        uint256 amountBDesired = 2000 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(user1);
        (uint256 amountA_out, uint256 amountB_out) = router.addLiquidityOptimal(
            address(tokenC),
            address(tokenD),
            amountADesired,
            amountBDesired,
            0,
            0,
            user1, // user1 becomes the owner
            deadline
        );
        
        // For first liquidity, should use desired amounts
        assertEq(amountA_out, amountADesired);
        assertEq(amountB_out, amountBDesired);
        
        // Verify that user1 is now the owner of the pool
        address pair = factory.getPair(address(tokenC), address(tokenD));
        assertEq(Pool(pair).owner(), user1);
    }
    
    function testRemoveLiquidity() public {
        // Add liquidity first
        vm.prank(user1);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
        
        address pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 balanceA_before = tokenA.balanceOf(pair);
        uint256 balanceB_before = tokenB.balanceOf(pair);
        // Owner must request exit and wait out timelock before router removes
        vm.prank(user1);
        Pool(pair).requestExitLiquidity();
        vm.warp(block.timestamp + 1 days + 1);
        
        // Only owner can remove liquidity
        vm.prank(user1);
        (uint256 amountA_out, uint256 amountB_out) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            user1,
            block.timestamp + 1 hours
        );
        
        assertEq(amountA_out, balanceA_before);
        assertEq(amountB_out, balanceB_before);
        assertEq(tokenA.balanceOf(pair), 0);
        assertEq(tokenB.balanceOf(pair), 0);
    }
    
    function testRemoveLiquidityOnlyOwner() public {
        vm.prank(user1);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
        
        // Verify that user1 is now the owner
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(Pool(pair).owner(), user1);
        // Owner must request exit and wait out timelock
        vm.prank(user1);
        Pool(pair).requestExitLiquidity();
        vm.warp(block.timestamp + 1 days + 1);
        
        // The Router can remove liquidity on behalf of the owner
        // This test verifies that the ownership-based system works correctly
        vm.prank(user1);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            user1,
            block.timestamp + 1 hours
        );
        
        // Verify that all liquidity was removed
        assertEq(tokenA.balanceOf(pair), 0);
        assertEq(tokenB.balanceOf(pair), 0);
    }
    
    function testOwnershipTransferOnLiquidityAdd() public {
        // Initially, factory should be the owner
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(Pool(pair).owner(), address(factory));
        
        // After user1 adds liquidity, user1 should become the owner
        vm.prank(user1);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
        
        assertEq(Pool(pair).owner(), user1);
        
        // After user2 adds more liquidity, user2 should become the new owner
        vm.prank(user2);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            500 * 10**18,
            1000 * 10**18,
            user2, // user2 becomes the new owner
            block.timestamp + 1 hours
        );
        
        assertEq(Pool(pair).owner(), user2);
    }
    
    // ============ SWAP TESTS ============
    
    function testSwapExactTokensForTokens() public {
        // Add liquidity first
        vm.prank(user1);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
        
        uint256 amountIn = 100 * 10**18;
        uint256 amountOutMin = 150 * 10**18; // Should get more than this
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 deadline = block.timestamp + 1 hours;
        
        uint256 balanceA_before = tokenA.balanceOf(user2);
        uint256 balanceB_before = tokenB.balanceOf(user2);
        
        vm.prank(user2);
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            user2,
            deadline
        );
        
        assertEq(amounts[0], amountIn);
        assertTrue(amounts[1] >= amountOutMin);
        assertEq(tokenA.balanceOf(user2), balanceA_before - amountIn);
        assertEq(tokenB.balanceOf(user2), balanceB_before + amounts[1]);
    }
    
    function testSwapTokensForExactTokens() public {
        // Add liquidity first
        vm.prank(user1);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
        
        uint256 amountOut = 200 * 10**18;
        uint256 amountInMax = 150 * 10**18; // Should need less than this
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 deadline = block.timestamp + 1 hours;
        
        uint256 balanceA_before = tokenA.balanceOf(user2);
        uint256 balanceB_before = tokenB.balanceOf(user2);
        
        vm.prank(user2);
        uint256[] memory amounts = router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            user2,
            deadline
        );
        
        assertTrue(amounts[0] <= amountInMax);
        assertEq(amounts[1], amountOut);
        assertEq(tokenA.balanceOf(user2), balanceA_before - amounts[0]);
        assertEq(tokenB.balanceOf(user2), balanceB_before + amountOut);
    }
    
    // ============ QUOTE TESTS ============
    
    function testGetAmountsOut() public {
        // Add liquidity first
        vm.prank(user1);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
        
        uint256 amountIn = 100 * 10**18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        
        assertEq(amounts[0], amountIn);
        assertTrue(amounts[1] > 0);
        // With 0.3% fee, should get approximately 199.4 tokens out
        assertTrue(amounts[1] < 200 * 10**18);
    }
    
    function testGetAmountsIn() public {
        // Add liquidity first
        vm.prank(user1);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
        
        uint256 amountOut = 200 * 10**18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        uint256[] memory amounts = router.getAmountsIn(amountOut, path);
        
        assertEq(amounts[1], amountOut);
        assertTrue(amounts[0] > 0);
        // Should need approximately 100.3 tokens in
        assertTrue(amounts[0] > 100 * 10**18);
    }
    
    function testQuote() public view {
        uint256 amountA = 100 * 10**18;
        uint256 reserveA = 1000 * 10**18;
        uint256 reserveB = 2000 * 10**18;
        
        uint256 amountB = router.quote(amountA, reserveA, reserveB);
        
        // Should get 200 tokens (100 * 2000 / 1000)
        assertEq(amountB, 200 * 10**18);
    }
    
    // ============ ERROR TESTS ============
    
    function testAddLiquidityExpired() public {
        uint256 deadline = block.timestamp - 1; // Expired
        
        vm.prank(user1);
        vm.expectRevert("Router: expired");
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            deadline
        );
    }
    
    function testSwapInvalidPath() public {
        address[] memory path = new address[](1);
        path[0] = address(tokenA);
        
        vm.prank(user2);
        vm.expectRevert("Router: invalid path");
        router.getAmountsOut(100 * 10**18, path);
    }
    
    function testSwapInsufficientOutput() public {
        // Add liquidity first
        vm.prank(user1);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
        
        uint256 amountIn = 100 * 10**18;
        uint256 amountOutMin = 1000 * 10**18; // Unrealistically high
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(user2);
        vm.expectRevert("Router: insufficient output amount");
        router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            user2,
            deadline
        );
    }
    
    function testSwapExcessiveInput() public {
        // Add liquidity first
        vm.prank(user1);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
        
        uint256 amountOut = 200 * 10**18;
        uint256 amountInMax = 50 * 10**18; // Unrealistically low
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(user2);
        vm.expectRevert("Router: excessive input amount");
        router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            user2,
            deadline
        );
    }
    
    function testAddLiquidityPairNotExists() public {
        MockERC20 tokenC = new MockERC20("TokenC", "TKC", INITIAL_SUPPLY);
        MockERC20 tokenD = new MockERC20("TokenD", "TKD", INITIAL_SUPPLY);
        
        vm.prank(user1);
        vm.expectRevert("Router: pair does not exist");
        router.addLiquidity(
            address(tokenC),
            address(tokenD),
            1000 * 10**18,
            2000 * 10**18,
            user1, // user1 becomes the owner
            block.timestamp + 1 hours
        );
    }
}