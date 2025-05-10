// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "balancer-v2-interfaces/vault/IVault.sol";
import "./ICappedLiquidity.sol";
import "./ILocallyPausable.sol";

interface IGyro2CLPPoolFactory {
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256[] memory sqrts,
        address[] memory rateProviders,
        uint256 swapFeePercentage,
        address owner,
        address capManager,
        ICappedLiquidity.CapParams memory capParams,
        address pauseManager,
        ILocallyPausable.PauseParams memory pauseParams
    ) external returns (address);

    function gyroConfigAddress() external returns (address);
}
