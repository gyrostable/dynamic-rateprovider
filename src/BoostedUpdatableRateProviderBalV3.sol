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
/// The `feed` must quote the price of the *underlying* assets (e.g. Chainlink ETH/USD for
/// waBasWETH/waBasUSDC). `updateToEdge()` needs no changes: the pool price in scaled units is
/// (true price of the underlying) / value, independent of the ERC-4626 rates of either leg,
/// provided the other leg's rateprovider reflects its own ERC-4626 rate.
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
    /// 0` initializes `value` to the feed value, *not* including the yield rate.
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
