// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "balancer-v2-interfaces/vault/IVault.sol";
import {ICappedLiquidity} from "./ICappedLiquidity.sol";
import {ILocallyPausable} from "./ILocallyPausable.sol";

interface IGyro3CLPPoolFactory {
    struct NewPoolConfigParams {
        string name;
        string symbol;
        IERC20[] tokens;
        address[] rateProviders;
        uint256 swapFeePercentage;
        uint256 root3Alpha;
        address owner;
        address capManager;
        ICappedLiquidity.CapParams capParams;
        address pauseManager;
        ILocallyPausable.PauseParams pauseParams;
    }

    function create(NewPoolConfigParams memory config) external returns (address);
}
