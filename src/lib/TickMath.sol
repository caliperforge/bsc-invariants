// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @title TickMath: Uniswap v3 tick + sqrtPriceX96 address-space constants.
/// @notice Reproduces the canonical `MIN_TICK`, `MAX_TICK`, `MIN_SQRT_RATIO`,
///         `MAX_SQRT_RATIO` from Uniswap v3 `TickMath.sol`. PancakeSwap v3
///         forks Uniswap v3 1:1 for tick / sqrtPriceX96 math; these constants
///         describe the protocol's address space, not new logic.
///
///         Upstream source (GPL-2.0-or-later):
///           https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol
///         Upstream PancakeSwap v3 mirror (GPL-2.0-or-later):
///           https://github.com/pancakeswap/pancake-v3-contracts/tree/main/projects/v3-core
///
///         Constants (facts about the address space) are reproduced here
///         under Apache-2.0; the upstream `getSqrtRatioAtTick` /
///         `getTickAtSqrtRatio` *implementations* are NOT reproduced; they
///         remain GPL-2.0-or-later at upstream. If a future milestone needs
///         those, we either (a) vendor the upstream file with its full GPL
///         header and re-evaluate the repo's license posture, or (b) link
///         against the upstream package as a git submodule with attribution.
///         The Week-1 invariants under test only require the bound
///         constants; the implementations are not on the critical path.
library TickMath {
    /// @dev The minimum tick that may be passed to `getSqrtRatioAtTick`
    ///      (Uniswap v3 convention; PancakeSwap v3 inherits 1:1).
    int24 internal constant MIN_TICK = -887272;

    /// @dev The maximum tick that may be passed to `getSqrtRatioAtTick`.
    int24 internal constant MAX_TICK = -MIN_TICK;

    /// @dev `getSqrtRatioAtTick(MIN_TICK)`; the minimum value that can be
    ///      returned by `getSqrtRatioAtTick`. Equivalent to `getSqrtRatioAtTick(MIN_TICK)`.
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;

    /// @dev `getSqrtRatioAtTick(MAX_TICK)`; the maximum value that can be
    ///      returned by `getSqrtRatioAtTick`. Equivalent to
    ///      `getSqrtRatioAtTick(MAX_TICK)`.
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
}
