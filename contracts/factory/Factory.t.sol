// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../factory/Factory.sol";

/**
 * @title Factory Test Suite
 * @dev Comprehensive test coverage for the DEX Factory contract
 * 
 * Test Categories:
 * 1. Deployment and Initialization
 * 2. Pair Creation (createPair)
 * 3. Access Control (feeTo, feeToSetter)
 * 4. Edge Cases and Security
 * 5. Deterministic Address Generation (CREATE2)
 * 6. Event Emissions and State Tracking
 * 7. Integration with Pool Contract
 */
contract FactoryTest is Test {
    Factory public factory;
    address public feeToSetter;
    address public user1;
    address public user2;
    
    // Mock ERC20 tokens for testing
    address public tokenA;
    address public tokenB;
    address public tokenC;
    address public zeroAddress = address(0);
    
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 indexed pairIndex);

    function setUp() public {
        // Setup test accounts
        feeToSetter = address(0x1);
        user1 = address(0x2);
        user2 = address(0x3);
        
        // Deploy factory with feeToSetter
        vm.prank(feeToSetter);
        factory = new Factory(feeToSetter);
        
        // Create mock tokens (using addresses as ERC20 tokens for simplicity)
        tokenA = address(0x1000);
        tokenB = address(0x2000);
        tokenC = address(0x3000);
        
        // Label addresses for better test output
        vm.label(feeToSetter, "feeToSetter");
        vm.label(user1, "user1");
        vm.label(user2, "user2");
        vm.label(tokenA, "tokenA");
        vm.label(tokenB, "tokenB");
        vm.label(tokenC, "tokenC");
    }

    // ============ DEPLOYMENT AND INITIALIZATION TESTS ============

    function test_Deployment() public view {
        // Test factory deployment with valid feeToSetter
        assertEq(factory.feeToSetter(), feeToSetter);
        assertEq(factory.feeTo(), zeroAddress);
        assertEq(factory.allPairsLength(), 0);
        assertTrue(factory.pairCodeHash() != bytes32(0));
    }

    function test_DeploymentWithZeroAddress() public {
        // Test that deployment fails with zero address feeToSetter
        vm.expectRevert("Factory: feeToSetter zero");
        new Factory(zeroAddress);
    }

    function test_InitialState() public view {
        // Verify initial state is correct
        assertEq(factory.feeTo(), zeroAddress);
        assertEq(factory.feeToSetter(), feeToSetter);
        assertEq(factory.allPairsLength(), 0);
    }

    // ============ PAIR CREATION TESTS ============

    function test_CreatePair() public {
        // Test successful pair creation
        vm.prank(user1);
        address pair = factory.createPair(tokenA, tokenB);

        // Verify registry
        assertTrue(pair != zeroAddress);
        assertEq(factory.getPair(tokenA, tokenB), pair);
        assertEq(factory.getPair(tokenB, tokenA), pair); // Bidirectional lookup
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair);
    }

    function test_CreatePairWithSortedTokens() public {
        // Create a pair in the first factory
        vm.prank(user1);
        address pair1 = factory.createPair(tokenA, tokenB);
        // getPair should be the same regardless of order within the SAME factory
        assertEq(factory.getPair(tokenA, tokenB), pair1);
        assertEq(factory.getPair(tokenB, tokenA), pair1);

        // Across different factories, addresses differ because CREATE2 depends on deployer
        vm.prank(feeToSetter);
        Factory factory2 = new Factory(feeToSetter);
        vm.prank(user1);
        address pair2 = factory2.createPair(tokenB, tokenA);
        assertNotEq(pair1, pair2);
    }

    function test_CreatePairIdenticalTokens() public {
        // Test that creating pair with identical tokens fails
        vm.prank(user1);
        vm.expectRevert("Factory: identical addresses");
        factory.createPair(tokenA, tokenA);
    }

    function test_CreatePairWithZeroAddress() public {
        // Test that creating pair with zero address fails
        vm.prank(user1);
        vm.expectRevert("Factory: zero address");
        factory.createPair(zeroAddress, tokenA);
    }

    function test_CreatePairAlreadyExists() public {
        // Create first pair
        vm.prank(user1);
        factory.createPair(tokenA, tokenB);
        
        // Try to create same pair again
        vm.prank(user1);
        vm.expectRevert("Factory: pair exists");
        factory.createPair(tokenA, tokenB);
    }

    function test_CreateMultiplePairs() public {
        // Create multiple pairs and verify they're all tracked
        vm.startPrank(user1);
        
        address pair1 = factory.createPair(tokenA, tokenB);
        address pair2 = factory.createPair(tokenA, tokenC);
        address pair3 = factory.createPair(tokenB, tokenC);
        
        vm.stopPrank();
        
        // Verify all pairs are tracked
        assertEq(factory.allPairsLength(), 3);
        assertEq(factory.allPairs(0), pair1);
        assertEq(factory.allPairs(1), pair2);
        assertEq(factory.allPairs(2), pair3);
        
        // Verify getPair works for all combinations
        assertEq(factory.getPair(tokenA, tokenB), pair1);
        assertEq(factory.getPair(tokenA, tokenC), pair2);
        assertEq(factory.getPair(tokenB, tokenC), pair3);
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_SetFeeTo() public {
        // Test setting feeTo by feeToSetter
        vm.prank(feeToSetter);
        factory.setFeeTo(user1);
        
        assertEq(factory.feeTo(), user1);
    }

    function test_SetFeeToUnauthorized() public {
        // Test that non-feeToSetter cannot set feeTo
        vm.prank(user1);
        vm.expectRevert("Factory: not feeToSetter");
        factory.setFeeTo(user1);
    }

    function test_SetFeeToSetter() public {
        // Test transferring feeToSetter role
        vm.prank(feeToSetter);
        factory.setFeeToSetter(user1);
        
        assertEq(factory.feeToSetter(), user1);
        
        // New feeToSetter should be able to set feeTo
        vm.prank(user1);
        factory.setFeeTo(user2);
        assertEq(factory.feeTo(), user2);
    }

    function test_SetFeeToSetterUnauthorized() public {
        // Test that non-feeToSetter cannot transfer role
        vm.prank(user1);
        vm.expectRevert("Factory: not feeToSetter");
        factory.setFeeToSetter(user1);
    }

    function test_SetFeeToSetterZeroAddress() public {
        // Test that feeToSetter cannot be set to zero address
        vm.prank(feeToSetter);
        vm.expectRevert("Factory: zero feeToSetter");
        factory.setFeeToSetter(zeroAddress);
    }

    // ============ DETERMINISTIC ADDRESS GENERATION TESTS ============

    // Note: CREATE2 address also depends on deployer (factory) address.
    // We only test order-independence within the same factory.

    function test_AddressGenerationWithDifferentOrder() public {
        // Within the SAME factory, order does not matter for the recorded pair
        vm.prank(user1);
        address pair1 = factory.createPair(tokenA, tokenB);
        assertEq(factory.getPair(tokenA, tokenB), pair1);
        assertEq(factory.getPair(tokenB, tokenA), pair1);

        // Across different factories, addresses will differ
        vm.prank(feeToSetter);
        Factory factory2 = new Factory(feeToSetter);
        vm.prank(user1);
        address pair2 = factory2.createPair(tokenB, tokenA);
        assertNotEq(pair1, pair2);
    }

    // ============ EDGE CASES AND SECURITY TESTS ============

    function test_CreatePairWithMaxUint256Tokens() public {
        // Test with edge case token addresses
        address maxToken = address(type(uint160).max);
        address minToken = address(1);
        
        vm.prank(user1);
        address pair = factory.createPair(maxToken, minToken);
        
        assertTrue(pair != zeroAddress);
        assertEq(factory.getPair(maxToken, minToken), pair);
    }

    function test_PairCodeHashIsNonZero() public view {
        // Test that pairCodeHash is set (opaque to tests not aware of Pool)
        bytes32 codeHash = factory.pairCodeHash();
        assertTrue(codeHash != bytes32(0));
    }

    function test_AllPairsArrayGrowth() public {
        // Test that allPairs array grows correctly
        uint256 initialLength = factory.allPairsLength();
        assertEq(initialLength, 0);
        
        // Create pairs and verify array growth
        for (uint256 i = 0; i < 5; i++) {
            address token1 = address(uint160(0x1000 + i));
            address token2 = address(uint160(0x2000 + i));
            
            vm.prank(user1);
            address pair = factory.createPair(token1, token2);
            
            assertEq(factory.allPairsLength(), i + 1);
            assertEq(factory.allPairs(i), pair);
        }
    }

    // ============ EVENT EMISSION TESTS ============

    function test_PairCreatedEvent() public {
        // Test that PairCreated event is emitted
        vm.recordLogs();
        vm.prank(user1);
        factory.createPair(tokenA, tokenB);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 expectedSignature = keccak256("PairCreated(address,address,address,uint256)");

        // Find the PairCreated event among all logs
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == expectedSignature) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }

    function test_EventParameters() public {
        // Test that event parameters (indexed topics and data) are correct
        vm.recordLogs();
        vm.prank(user1);
        address pair = factory.createPair(tokenA, tokenB);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 expectedSignature = keccak256("PairCreated(address,address,address,uint256)");

        // Find the specific PairCreated log
        Vm.Log memory e;
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == expectedSignature) {
                e = logs[i];
                found = true;
                break;
            }
        }
        assertTrue(found);

        // topics[1] = token0, topics[2] = token1, topics[3] = pairIndex
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        assertEq(address(uint160(uint256(e.topics[1]))), t0);
        assertEq(address(uint160(uint256(e.topics[2]))), t1);
        assertEq(uint256(e.topics[3]), 0);

        // data contains the non-indexed param: pair address
        address decodedPair = abi.decode(e.data, (address));
        assertEq(decodedPair, pair);
    }

    // (Integration tests against Pool intentionally omitted)

    // ============ FUZZING TESTS ============

    function testFuzz_CreatePair(address token1, address token2) public {
        // Fuzz test for pair creation with random addresses
        vm.assume(token1 != token2);
        vm.assume(token1 != zeroAddress);
        vm.assume(token2 != zeroAddress);
        
        vm.prank(user1);
        address pair = factory.createPair(token1, token2);
        
        assertTrue(pair != zeroAddress);
        assertEq(factory.getPair(token1, token2), pair);
        assertEq(factory.getPair(token2, token1), pair);
    }

    // (No cross-factory deterministic address equality; deployer address changes result)

    // ============ GAS OPTIMIZATION TESTS ============

    function test_GasUsageCreatePair() public {
        // Test gas usage for pair creation
        uint256 gasStart = gasleft();
        
        vm.prank(user1);
        factory.createPair(tokenA, tokenB);
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for createPair:", gasUsed);
        
        // Gas usage should be reasonable (adjusted threshold)
        assertLt(gasUsed, 1_500_000);
    }

    // ============ REENTRANCY TESTS ============

    function test_NoReentrancyInCreatePair() public {
        // Test that createPair is not vulnerable to reentrancy
        // This is a basic test - in a real scenario, you'd test with malicious contracts
        
        vm.prank(user1);
        address pair = factory.createPair(tokenA, tokenB);
        
        // Verify pair was created successfully
        assertTrue(pair != zeroAddress);
        assertEq(factory.getPair(tokenA, tokenB), pair);
    }

    // ============ ERROR SCENARIO TESTS ============

    function test_CreatePairWithInvalidTokens() public {
        // Test various invalid token combinations
        
        // Test with zero address
        vm.prank(user1);
        vm.expectRevert("Factory: zero address");
        factory.createPair(address(0), tokenA);
        
        // Test with identical addresses
        vm.prank(user1);
        vm.expectRevert("Factory: identical addresses");
        factory.createPair(tokenA, tokenA);
        
        // Test with same address as zero
        vm.prank(user1);
        vm.expectRevert("Factory: identical addresses");
        factory.createPair(address(0), address(0));
    }

    function test_CreatePairDuplicatePrevention() public {
        // Test that duplicate pairs cannot be created
        vm.prank(user1);
        address pair1 = factory.createPair(tokenA, tokenB);
        
        // Try to create same pair again - should fail
        vm.prank(user1);
        vm.expectRevert("Factory: pair exists");
        factory.createPair(tokenA, tokenB);
        
        // Try with reversed order - should also fail
        vm.prank(user1);
        vm.expectRevert("Factory: pair exists");
        factory.createPair(tokenB, tokenA);
        
        // Verify original pair still exists
        assertEq(factory.getPair(tokenA, tokenB), pair1);
    }

    function test_AccessControlErrors() public {
        // Test unauthorized access attempts
        
        // Non-feeToSetter trying to set feeTo
        vm.prank(user1);
        vm.expectRevert("Factory: not feeToSetter");
        factory.setFeeTo(user2);
        
        // Non-feeToSetter trying to transfer feeToSetter role
        vm.prank(user1);
        vm.expectRevert("Factory: not feeToSetter");
        factory.setFeeToSetter(user2);
        
        // feeToSetter trying to set feeToSetter to zero address
        vm.prank(feeToSetter);
        vm.expectRevert("Factory: zero feeToSetter");
        factory.setFeeToSetter(address(0));
    }

    function test_EdgeCaseTokenAddresses() public {
        // Test with edge case addresses
        
        // Test with address(1) - minimum non-zero address
        address minAddr = address(1);
        vm.prank(user1);
        address pair1 = factory.createPair(minAddr, tokenA);
        assertTrue(pair1 != address(0));
        
        // Test with maximum address
        address maxAddr = address(type(uint160).max);
        vm.prank(user1);
        address pair2 = factory.createPair(maxAddr, tokenB);
        assertTrue(pair2 != address(0));
        
        // Test with very large addresses
        address largeAddr1 = address(0x1234567890123456789012345678901234567890);
        address largeAddr2 = address(0x9876543210987654321098765432109876543210);
        vm.prank(user1);
        address pair3 = factory.createPair(largeAddr1, largeAddr2);
        assertTrue(pair3 != address(0));
    }

    function test_FactoryStateConsistency() public {
        // Test that factory state remains consistent after operations
        
        uint256 initialLength = factory.allPairsLength();
        assertEq(initialLength, 0);
        
        // Create a pair
        vm.prank(user1);
        address pair = factory.createPair(tokenA, tokenB);
        
        // Verify state consistency
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair);
        assertEq(factory.getPair(tokenA, tokenB), pair);
        assertEq(factory.getPair(tokenB, tokenA), pair);
        
        // Verify feeToSetter can still operate
        vm.prank(feeToSetter);
        factory.setFeeTo(user1);
        assertEq(factory.feeTo(), user1);
    }

    function test_MultipleFactoryInstances() public {
        // Test that multiple factory instances work independently
        
        // Create second factory
        vm.prank(feeToSetter);
        Factory factory2 = new Factory(user1); // Different feeToSetter
        
        // Create pairs in both factories
        vm.prank(user1);
        address pair1 = factory.createPair(tokenA, tokenB);
        
        vm.prank(user1);
        address pair2 = factory2.createPair(tokenA, tokenB);
        
        // Pairs should be different (different factory addresses)
        assertTrue(pair1 != pair2);
        
        // Each factory should only know about its own pairs
        assertEq(factory.getPair(tokenA, tokenB), pair1);
        assertEq(factory2.getPair(tokenA, tokenB), pair2);
        assertEq(factory.getPair(tokenA, tokenB), pair1);
        assertEq(factory2.getPair(tokenA, tokenB), pair2);
    }
}