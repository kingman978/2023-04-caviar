// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";
import "../../src/PrivatePool.sol";

contract BuyTest is Fixture {
    PrivatePool public privatePool;

    address baseToken = address(0);
    address nft = address(milady);
    uint128 virtualBaseTokenReserves = 100e18;
    uint128 virtualNftReserves = 5e18;
    uint16 feeRate = 0;
    bytes32 merkleRoot = bytes32(abi.encode(0));
    address owner = address(this);

    uint256[] tokenIds;
    uint256[] tokenWeights;
    PrivatePool.MerkleMultiProof proof;

    function setUp() public {
        privatePool = new PrivatePool();
        privatePool.initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            owner
        );

        for (uint256 i = 0; i < 5; i++) {
            milady.mint(address(privatePool), i);
        }
    }

    function test_RefundsExcessEth() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);
        uint256 surplus = 0.123e18;
        uint256 balanceBefore = address(this).balance;

        // act
        privatePool.buy{value: netInputAmount + surplus}(tokenIds, tokenWeights, proof);

        // assert
        assertEq(
            balanceBefore - address(this).balance,
            netInputAmount,
            "Should have refunded anything surplus to netInputAmount"
        );
    }

    function test_ReturnsNetInputAmount() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        (uint256 returnedNetInputAmount,) = privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proof);

        // assert
        assertEq(returnedNetInputAmount, netInputAmount, "Should have returned netInputAmount");
    }

    function test_TransfersNftsToCaller() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proof);

        // assert
        assertEq(milady.balanceOf(address(this)), tokenIds.length, "Should have incremented callers NFT balance");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(milady.ownerOf(tokenIds[i]), address(this), "Should have transferred NFTs to caller");
        }
    }

    function test_TransfersBaseTokensToPair() public {
        // arrange
        privatePool = new PrivatePool();
        privatePool.initialize(
            address(shibaInu),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            owner
        );

        for (uint256 i = 10; i < 13; i++) {
            tokenIds.push(i);
            milady.mint(address(privatePool), i);
        }

        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);
        deal(address(shibaInu), address(this), netInputAmount);
        shibaInu.approve(address(privatePool), netInputAmount);
        uint256 poolBalanceBefore = shibaInu.balanceOf(address(privatePool));
        uint256 callerBalanceBefore = shibaInu.balanceOf(address(this));

        // act
        privatePool.buy(tokenIds, tokenWeights, proof);

        // assert
        assertEq(
            shibaInu.balanceOf(address(privatePool)) - poolBalanceBefore,
            netInputAmount,
            "Should have transferred tokens to pool"
        );

        assertEq(
            callerBalanceBefore - shibaInu.balanceOf(address(this)),
            netInputAmount,
            "Should have transferred tokens from caller"
        );
    }

    function test_UpdatesVirtualReserves() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);
        uint256 virtualBaseTokenReservesBefore = privatePool.virtualBaseTokenReserves();
        uint256 virtualNftReservesBefore = privatePool.virtualNftReserves();

        // act
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proof);

        // assert
        assertEq(
            privatePool.virtualBaseTokenReserves(),
            virtualBaseTokenReservesBefore + netInputAmount,
            "Should have incremented virtualBaseTokenReserves"
        );

        assertEq(
            privatePool.virtualNftReserves(),
            virtualNftReservesBefore - tokenIds.length * 1e18,
            "Should have decremented virtualNftReserves"
        );
    }

    function test_RevertIf_CallerSentLessEthThanNetInputAmount() public {
        // arrange
        tokenIds.push(1);
        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        privatePool.buy{value: netInputAmount - 1}(tokenIds, tokenWeights, proof);
    }

    function test_RevertIf_CallerSentEthAndBaseTokenIsNotSetAsEth() public {
        // arrange
        privatePool = new PrivatePool();
        privatePool.initialize(
            address(shibaInu),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            owner
        );

        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        privatePool.buy{value: 100}(tokenIds, tokenWeights, proof);
    }
}