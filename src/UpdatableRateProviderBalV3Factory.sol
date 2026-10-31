// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.

pragma solidity ^0.8.24;

import {Ownable} from "oz/access/Ownable.sol";

import {UpdatableRateProviderBalV3} from "./UpdatableRateproviderBalV3.sol";

/// @notice Factory for deploying and managing Balancer V3 updatable rate providers.
/// @dev Create always deploys a new instance (no uniqueness by feed/params): the same feed may
/// be used across many pools, and each pool needs its own rate provider.
contract UpdatableRateProviderBalV3Factory is Ownable {
    /// @notice A new updatable rate provider was created.
    event RateProviderCreated(
        address indexed feed,
        bool invert,
        uint256 initialValue,
        address admin,
        address updater,
        address indexed rateProvider
    );

    /// @notice Emitted when the factory is disabled.
    event RateProviderFactoryDisabled();

    /// @notice The factory is disabled.
    error RateProviderFactoryIsDisabled();

    /// @notice Human-readable factory version string.
    string public version;

    /// @notice Numeric version of rate providers deployed by this factory.
    uint256 internal immutable _rateProviderVersion;

    bool internal _isDisabled;

    mapping(address rateProvider => bool creationFlag) internal _isRateProviderFromFactory;

    /// @param owner_ Address that can call `disable()`
    /// @param factoryVersion Human-readable factory version
    /// @param rateProviderVersion Numeric version stamped on this factory for deployed URPs
    constructor(address owner_, string memory factoryVersion, uint256 rateProviderVersion)
        Ownable(owner_)
    {
        version = factoryVersion;
        _rateProviderVersion = rateProviderVersion;
    }

    /// @notice Returns a number representing the rate provider version.
    function getRateProviderVersion() external view returns (uint256) {
        return _rateProviderVersion;
    }

    /// @notice Creates a new `UpdatableRateProviderBalV3`.
    /// @param feed A RateProvider to use for updates
    /// @param invert If true, use 1/(feed value) instead of the feed value itself
    /// @param initialValue If not 0, use this as the initial stored rate; if 0, use the feed
    /// @param admin Address for `DEFAULT_ADMIN_ROLE` (can `setPool()` and manage roles)
    /// @param updater Address for `UPDATER_ROLE` (can `updateToEdge()`); pass zero to leave unset
    /// @return rateProvider The deployed rate provider
    function create(
        address feed,
        bool invert,
        uint256 initialValue,
        address admin,
        address updater
    ) external returns (UpdatableRateProviderBalV3 rateProvider) {
        _ensureEnabled();

        rateProvider = new UpdatableRateProviderBalV3(feed, invert, initialValue, admin, updater);
        _isRateProviderFromFactory[address(rateProvider)] = true;

        emit RateProviderCreated(feed, invert, initialValue, admin, updater, address(rateProvider));
    }

    /// @notice Checks whether the given rate provider was created by this factory.
    function isRateProviderFromFactory(address rateProvider) external view returns (bool) {
        return _isRateProviderFromFactory[rateProvider];
    }

    /// @notice Disables the factory. One-way; already created rate providers remain usable.
    function disable() external onlyOwner {
        _ensureEnabled();

        _isDisabled = true;
        emit RateProviderFactoryDisabled();
    }

    function _ensureEnabled() internal view {
        if (_isDisabled) {
            revert RateProviderFactoryIsDisabled();
        }
    }
}
