// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {TickMath} from "./lib/TickMath.sol";

/// @title PancakeV3LiquidityEventsRef — minimal v3 mint/burn + active-liquidity reference.
/// @notice A same-source twin minimal to the P-4 LiquidityEventConsistency
///         invariant (SCOPE.md §1 P-4). It is NOT a fork of PancakeSwap's
///         production v3 pool — only the mint/burn surface and the
///         active-liquidity update rule for in-range positions are reproduced.
///
///         The canonical Uniswap v3 / PancakeSwap v3 rule (see
///         `UniswapV3Pool.sol::_modifyPosition`): a mint/burn operation on a
///         position `[tickLower, tickUpper)` updates the pool's active
///         `liquidity` by exactly `±amount` IF AND ONLY IF the current
///         `tick` lies in `[tickLower, tickUpper)`. Out-of-range positions
///         update the per-position storage but leave active `liquidity`
///         untouched.
///
///         The reference omits the fee-growth-inside computation (that's
///         P-5 and a sibling reference). It also omits tick-spacing
///         enforcement; the property is about arithmetic, not tick
///         alignment.
contract PancakeV3LiquidityEventsRef {
    // ---------------------------------------------------------------------
    // Pool state (the subset the P-4 invariant exercises)
    // ---------------------------------------------------------------------

    /// @notice Current pool tick. Settable via `crossTick` to simulate the
    ///         price moving across position boundaries between mint/burn ops.
    int24 public tick;

    /// @notice Active liquidity. The load-bearing storage P-4 asserts on.
    uint128 public liquidity;

    /// @notice Per-position liquidity. Keyed by
    ///         `keccak256(owner, tickLower, tickUpper)`. Mirrors
    ///         `Pool.positions[bytes32]` for the liquidity field only.
    mapping(bytes32 => uint128) public positionLiquidity;

    // ---------------------------------------------------------------------
    // Events (for invariant traces)
    // ---------------------------------------------------------------------

    event Mint(
        address indexed owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bool inRange,
        uint128 newActiveLiquidity
    );
    event Burn(
        address indexed owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bool inRange,
        uint128 newActiveLiquidity
    );
    event TickCrossed(int24 oldTick, int24 newTick);

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    constructor(int24 _initialTick, uint128 _initialLiquidity) {
        require(_initialTick >= TickMath.MIN_TICK, "tick<MIN");
        require(_initialTick <= TickMath.MAX_TICK, "tick>MAX");
        tick = _initialTick;
        liquidity = _initialLiquidity;
    }

    // ---------------------------------------------------------------------
    // The mutating surface the P-4 invariant exercises
    // ---------------------------------------------------------------------

    /// @notice Mint liquidity into a position. If the current tick is in
    ///         `[tickLower, tickUpper)`, active `liquidity` increases by
    ///         exactly `amount`; otherwise active `liquidity` is unchanged.
    ///         The position's stored liquidity always increases by `amount`.
    function mint(address owner, int24 tickLower, int24 tickUpper, uint128 amount) external {
        _validateRange(tickLower, tickUpper);
        require(amount > 0, "amount=0");

        bytes32 key = _positionKey(owner, tickLower, tickUpper);
        // Position-side update is unconditional — out-of-range mints are
        // legitimate (LPs frequently pre-position liquidity for an expected
        // price move).
        positionLiquidity[key] += amount;

        bool inRange = (tick >= tickLower) && (tick < tickUpper);
        if (inRange) {
            liquidity = _u128(uint256(liquidity) + uint256(amount));
        }

        emit Mint(owner, tickLower, tickUpper, amount, inRange, liquidity);
    }

    /// @notice Burn liquidity from a position. If the current tick is in
    ///         `[tickLower, tickUpper)`, active `liquidity` decreases by
    ///         exactly `amount`. The position's stored liquidity always
    ///         decreases by `amount`. Reverts if the position's stored
    ///         liquidity is less than `amount`.
    function burn(address owner, int24 tickLower, int24 tickUpper, uint128 amount) external {
        _validateRange(tickLower, tickUpper);
        require(amount > 0, "amount=0");

        bytes32 key = _positionKey(owner, tickLower, tickUpper);
        uint128 stored = positionLiquidity[key];
        require(stored >= amount, "burn>position");
        unchecked {
            // stored >= amount checked above; subtraction is safe.
            positionLiquidity[key] = stored - amount;
        }

        bool inRange = (tick >= tickLower) && (tick < tickUpper);
        if (inRange) {
            // If the in-range invariant held on every mint, active liquidity
            // is at least `amount`. A revert here would indicate a P-4
            // violation; we let the unchecked-on-checked Solidity underflow
            // surface naturally if the pool was constructed inconsistently.
            require(liquidity >= amount, "active<burn");
            unchecked {
                liquidity = liquidity - amount;
            }
        }

        emit Burn(owner, tickLower, tickUpper, amount, inRange, liquidity);
    }

    /// @notice Move the pool's tick. Mirrors the effect of a swap crossing
    ///         tick boundaries; we don't model the swap itself here (that's
    ///         the fee-growth refs). A real v3 pool flips
    ///         `feeGrowthOutsideXX128` per crossed tick and updates active
    ///         `liquidity` by the per-tick `liquidityNet`; the P-4
    ///         invariant is about mint/burn arithmetic, not the cross
    ///         update, so this simplified operation is sufficient.
    function crossTick(int24 newTick) external {
        require(newTick >= TickMath.MIN_TICK, "tick<MIN");
        require(newTick <= TickMath.MAX_TICK, "tick>MAX");
        emit TickCrossed(tick, newTick);
        tick = newTick;
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _validateRange(int24 tickLower, int24 tickUpper) internal pure {
        require(tickLower < tickUpper, "tickLower>=tickUpper");
        require(tickLower >= TickMath.MIN_TICK, "tickLower<MIN");
        require(tickUpper <= TickMath.MAX_TICK, "tickUpper>MAX");
    }

    function _positionKey(address owner, int24 tickLower, int24 tickUpper) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, tickLower, tickUpper));
    }

    function _u128(uint256 v) internal pure returns (uint128) {
        require(v <= type(uint128).max, "liquidity>uint128");
        return uint128(v);
    }
}
