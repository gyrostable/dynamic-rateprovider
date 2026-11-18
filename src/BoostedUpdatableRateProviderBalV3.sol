// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.

pragma solidity ^0.8.24;

import {UpdatableRateProviderBalV3} from "./UpdatableRateproviderBalV3.sol";
import {IRateProvider} from "balancer-v3-interfaces/solidity-utils/helpers/IRateProvider.sol";
import {FixedPoint} from "balancer-v3/pkg/solidity-utils/contracts/math/FixedPoint.sol";

/// @notice Variant of `UpdatableRateProviderBalV3` for yield-bearing ("boosted") pool tokens, e.g.
/// an ERC-4626 wrapper like waBasWETH paired with waBasUSDC. The rate returned is the updatable
/// `value` multiplied by the live rate of `yieldRateProvider` (e.g. an `ERC4626RateProvider`).
///
/// The `feed` must quote the price of the *underlying* of this token in units of the underlying of
/// the paired token (e.g. Chainlink ETH/USD for waBasWETH paired with waBasUSDC), regardless of
/// whether this token is token0 or token1. `updateToEdge()` needs no changes: the inner pool price
/// (token0 in units of token1, in scaled units) is independent of the ERC-4626 rates of either leg,
/// provided the other leg's rateprovider reflects its own ERC-4626 rate. Specifically:
/// - If this rateprovider is on token0 (`ourTokenIx == 0`, e.g. waBasWETH/waBasUSDC), the inner
///   pool price is (true price of underlying 0 in 1) / `value`.
/// - If this rateprovider is on token1 (`ourTokenIx == 1`, e.g. waBasUSDC/waBasWETH), the inner
///   pool price is `value` / (true price of underlying 1 in 0).
/// In both cases, use the feed as-is (`_invert = false`); do *not* invert just because this token
/// is token1.
///
/// Pool registration: `paysYieldFees` must be false on the token using this rateprovider
/// (`setPool()` reverts otherwise). Consequently, no protocol yield fees are taken on the yield of
/// this token. The paired token can use its standard rateprovider with `paysYieldFees = true`.
contract BoostedUpdatableRateProviderBalV3 is UpdatableRateProviderBalV3 {
    using FixedPoint for uint256;

    /// @notice Live rate of the yield-bearing wrapper, multiplied onto `value`. If the zero
    /// address, this contract behaves exactly like `UpdatableRateProviderBalV3`.
    IRateProvider public immutable yieldRateProvider;

    /// @param _yieldRateProvider Rateprovider for the yield-bearing wrapper (e.g.
    ///     `ERC4626RateProvider(waBasWETH)`), or the zero address for none.
    /// @dev See `UpdatableRateProviderBalV3` for the other parameters. Note that `_initialValue =
    /// 0` initializes `value` to the feed value, *not* including the yield rate, and a non-zero
    /// `_initialValue` must likewise be specified pre-yield (i.e., without multiplying by
    /// `yieldRateProvider.getRate()`); otherwise the yield rate is applied twice.
    constructor(
        address _feed,
        bool _invert,
        uint256 _initialValue,
        address _admin,
        address _updater,
        address _yieldRateProvider
    ) UpdatableRateProviderBalV3(_feed, _invert, _initialValue, _admin, _updater) {
        yieldRateProvider = IRateProvider(_yieldRateProvider);
    }

    /// @notice `value` times the live rate of `yieldRateProvider` (or just `value` if unset).
    function getRate() external view override returns (uint256) {
        return address(yieldRateProvider) == ZERO_ADDRESS
            ? value
            : value.mulDown(yieldRateProvider.getRate());
    }
}
