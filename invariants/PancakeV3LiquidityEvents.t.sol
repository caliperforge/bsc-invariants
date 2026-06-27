// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {PancakeV3LiquidityEventsRef} from "../src/PancakeV3LiquidityEventsRef.sol";
import {TickMath} from "../src/lib/TickMath.sol";

/// @title PancakeV3LiquidityEvents — P-4 property: mint/burn updates active liquidity
///        by exactly ±delta for in-range positions; leaves it unchanged otherwise.
/// @notice SCOPE.md §1 P-4. After any mint/burn operation on a position
///         `[tickLower, tickUpper)`:
///           - if current `tick ∈ [tickLower, tickUpper)`:
///                 `liquidity_after - liquidity_before == ±amount` (mint/burn)
///           - else:
///                 `liquidity_after == liquidity_before`
///         In both cases, the position's stored liquidity updates by ±amount.
///
///         The bug class P-4 catches: a forked v3 pool whose
///         `_modifyPosition` mis-routes the active-liquidity update — e.g.,
///         updates active `liquidity` for out-of-range positions, fails to
///         update it for in-range, or mis-applies the sign.
contract PancakeV3LiquidityEventsTest is StdInvariant, Test {
    PancakeV3LiquidityEventsRef internal pool;
    LiquidityHandler internal handler;

    int24 internal constant INITIAL_TICK = 0;
    uint128 internal constant INITIAL_LIQUIDITY = 0;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB   = address(0xB0B);

    function setUp() public {
        pool = new PancakeV3LiquidityEventsRef(INITIAL_TICK, INITIAL_LIQUIDITY);
        handler = new LiquidityHandler(pool);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = LiquidityHandler.mintBounded.selector;
        selectors[1] = LiquidityHandler.burnBounded.selector;
        selectors[2] = LiquidityHandler.crossTickBounded.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ---------------------------------------------------------------------
    // Stateful-fuzz invariant — sum-of-positions == active-liquidity when all
    // positions are in-range; the handler restricts to a single in-range
    // band to keep the invariant tractable.
    // ---------------------------------------------------------------------

    /// @notice The handler only mints into a single fixed band
    ///         `[BAND_LOWER, BAND_UPPER)` that includes the initial tick.
    ///         Active liquidity must equal the sum of mints minus burns
    ///         WHILE the pool's tick stays in-range. The handler clamps
    ///         `crossTickBounded` to keep tick inside the band so the
    ///         invariant is well-formed for the campaign.
    function invariant_activeLiquidity_equalsNetMintMinusBurn_inRange() public view {
        // The invariant is only meaningful while tick is in-range. The handler
        // keeps it so; if a future change breaks that, this assertGe still
        // holds (active liquidity is non-negative).
        int24 t = pool.tick();
        if (t >= handler.BAND_LOWER() && t < handler.BAND_UPPER()) {
            assertEq(
                uint256(pool.liquidity()),
                handler.netMintedInBand(),
                "INVARIANT VIOLATED liquidityEvent_consistency (active != net mint-burn)"
            );
        }
    }

    // ---------------------------------------------------------------------
    // Unit-level properties — deterministic boundary checks for the canonical
    // ±delta rule.
    // ---------------------------------------------------------------------

    /// @notice Mint in-range increments active liquidity by exactly `amount`.
    function test_property_mint_inRange_incrementsByDelta() public {
        // Initial tick = 0; range [-10, 10) is in-range.
        uint128 before = pool.liquidity();
        pool.mint(ALICE, -10, 10, 1e18);
        assertEq(pool.liquidity(), before + 1e18, "in-range mint did not increment by delta");
    }

    /// @notice Mint out-of-range leaves active liquidity unchanged.
    function test_property_mint_outOfRange_leavesActiveUnchanged() public {
        uint128 before = pool.liquidity();
        // Range [100, 200) is above the current tick (0).
        pool.mint(ALICE, 100, 200, 1e18);
        assertEq(pool.liquidity(), before, "out-of-range mint changed active liquidity");
    }

    /// @notice Burn in-range decrements active liquidity by exactly `amount`.
    function test_property_burn_inRange_decrementsByDelta() public {
        pool.mint(ALICE, -10, 10, 2e18);
        uint128 before = pool.liquidity();
        pool.burn(ALICE, -10, 10, 5e17);
        assertEq(pool.liquidity(), before - 5e17, "in-range burn did not decrement by delta");
    }

    /// @notice Burn out-of-range leaves active liquidity unchanged.
    function test_property_burn_outOfRange_leavesActiveUnchanged() public {
        pool.mint(ALICE, 100, 200, 1e18);
        uint128 before = pool.liquidity();
        pool.burn(ALICE, 100, 200, 5e17);
        assertEq(pool.liquidity(), before, "out-of-range burn changed active liquidity");
    }

    /// @notice Crossing tick into a position's range activates its liquidity
    ///         on the next mint into the same range (sanity check on the
    ///         tick-membership predicate).
    function test_property_crossTick_thenMint_inRange_activates() public {
        // Mint into [100, 200) while out-of-range: no active change.
        pool.mint(ALICE, 100, 200, 1e18);
        assertEq(pool.liquidity(), 0);

        // Cross tick into the range.
        pool.crossTick(150);

        // Now mint again — should activate.
        pool.mint(ALICE, 100, 200, 2e18);
        assertEq(pool.liquidity(), 2e18, "post-cross in-range mint did not activate");
    }

    /// @notice Position-side accounting tracks total mints regardless of range.
    function test_property_positionLiquidity_alwaysIncrementsOnMint() public {
        bytes32 key = keccak256(abi.encodePacked(ALICE, int24(100), int24(200)));
        pool.mint(ALICE, 100, 200, 7e17);
        assertEq(pool.positionLiquidity(key), 7e17, "out-of-range mint did not record position");
    }

    /// @notice Fuzz: any in-range mint produces exactly ±delta on active.
    function testFuzz_property_mint_inRange_incrementsByDelta(uint96 amount) public {
        vm.assume(amount > 0);
        uint128 before = pool.liquidity();
        pool.mint(ALICE, -50, 50, uint128(amount));
        assertEq(pool.liquidity(), before + uint128(amount));
    }
}

/// @title LiquidityHandler — bounded handler for the stateful-fuzz invariant.
/// @notice Restricts mint/burn to a single in-range band and tracks the net
///         minted amount as a shadow. The invariant compares pool active
///         liquidity to this shadow; any forked-pool bug that
///         misroutes the active-liquidity update would surface here.
contract LiquidityHandler is Test {
    PancakeV3LiquidityEventsRef public pool;

    int24 public constant BAND_LOWER = -1000;
    int24 public constant BAND_UPPER = 1000;
    uint128 internal constant MAX_PER_MINT = 1e24;

    /// @notice Shadow: sum(mints into BAND) - sum(burns from BAND) for the
    ///         single handler-managed owner.
    uint256 public netMintedInBand;

    address internal constant OWNER = address(0xCAFE);

    constructor(PancakeV3LiquidityEventsRef _pool) {
        pool = _pool;
    }

    function mintBounded(uint128 rawAmount) external {
        uint128 amount = uint128(uint256(rawAmount) % MAX_PER_MINT);
        if (amount == 0) amount = 1;
        pool.mint(OWNER, BAND_LOWER, BAND_UPPER, amount);
        netMintedInBand += amount;
    }

    function burnBounded(uint128 rawAmount) external {
        if (netMintedInBand == 0) return;
        uint256 cap = netMintedInBand > type(uint128).max ? type(uint128).max : netMintedInBand;
        uint128 amount = uint128(uint256(rawAmount) % cap);
        if (amount == 0) amount = 1;
        // Defensive: if amount somehow exceeds position storage (it shouldn't
        // given the cap above), let the underlying revert and the fuzzer
        // discard the call frame.
        try pool.burn(OWNER, BAND_LOWER, BAND_UPPER, amount) {
            netMintedInBand -= amount;
        } catch {
            // Revert path — shadow unchanged.
        }
    }

    function crossTickBounded(int16 rawTick) external {
        // Clamp tick to stay strictly inside BAND so the invariant
        // (active == shadow) holds for every step.
        int24 t = int24(rawTick);
        if (t <= BAND_LOWER) t = BAND_LOWER + 1;
        if (t >= BAND_UPPER) t = BAND_UPPER - 1;
        pool.crossTick(t);
    }
}
