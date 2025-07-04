// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.0;
// pragma experimental ABIEncoderV2;

import "balancer-v2-interfaces/vault/IVault.sol";
import "./ICappedLiquidity.sol";
import "./ILocallyPausable.sol";

interface IGyroECLPPoolFactory {
    struct Params {
        // Price bounds (lower and upper). 0 < alpha < beta
        int256 alpha;
        int256 beta;
        // Rotation vector:
        // phi in (-90 degrees, 0] is the implicit rotation vector. It's stored as a point:
        int256 c; // c = cos(-phi) >= 0. rounded to 18 decimals
        int256 s; //  s = sin(-phi) >= 0. rounded to 18 decimals
        // Invariant: c^2 + s^2 == 1, i.e., the point (c, s) is normalized.
        // due to rounding, this may not = 1. The term dSq in DerivedParams corrects for this in
        // extra precision

        // Stretching factor:
        int256 lambda; // lambda >= 1 where lambda == 1 is the circle.
    }

    // terms in this struct are stored in extra precision (38 decimals) with final decimal rounded
    // down
    struct DerivedParams {
        Vector2 tauAlpha;
        Vector2 tauBeta;
        int256 u; // from (A chi)_y = lambda * u + v
        int256 v; // from (A chi)_y = lambda * u + v
        int256 w; // from (A chi)_x = w / lambda + z
        int256 z; // from (A chi)_x = w / lambda + z
        int256 dSq; // error in c^2 + s^2 = dSq, used to correct errors in c, s, tau, u,v,w,z
            // calculations
            //int256 dAlpha; // normalization constant for tau(alpha)
            //int256 dBeta; // normalization constant for tau(beta)
    }

    struct Vector2 {
        int256 x;
        int256 y;
    }

    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        Params memory eclpParams,
        DerivedParams memory derivedECLPParams,
        address[] memory rateProviders,
        uint256 swapFeePercentage,
        address owner,
        address capManager,
        ICappedLiquidity.CapParams memory capParams,
        address pauseManager,
        ILocallyPausable.PauseParams memory pauseParams
    ) external returns (address);
}
