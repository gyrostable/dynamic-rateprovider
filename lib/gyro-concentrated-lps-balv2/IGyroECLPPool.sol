
pragma solidity ^0.8;

import {IGyroBasePool} from "./IGyroBasePool.sol";

/// @notice This is an ad-hoc interface for required functions of ECLPs under Balancer v2.
/// See https://github.com/gyrostable/concentrated-lps/blob/main/contracts/eclp/GyroECLPPool.sol
interface IGyroECLPPool is IGyroBasePool {
    // See https://github.com/gyrostable/concentrated-lps/blob/main/contracts/eclp/GyroECLPMath.sol

    struct Vector2 {
        int256 x;
        int256 y;
    }

    struct Params {
        // Price bounds (lower and upper). 0 < alpha < beta
        int256 alpha;
        int256 beta;
        // Rotation vector:
        // phi in (-90 degrees, 0] is the implicit rotation vector. It's stored as a point:
        int256 c; // c = cos(-phi) >= 0. rounded to 18 decimals
        int256 s; //  s = sin(-phi) >= 0. rounded to 18 decimals
        // Invariant: c^2 + s^2 == 1, i.e., the point (c, s) is normalized.
        // due to rounding, this may not = 1. The term dSq in DerivedParams corrects for this in extra precision

        // Stretching factor:
        int256 lambda; // lambda >= 1 where lambda == 1 is the circle.
    }

    // terms in this struct are stored in extra precision (38 decimals) with final decimal rounded down
    struct DerivedParams {
        Vector2 tauAlpha;
        Vector2 tauBeta;
        int256 u; // from (A chi)_y = lambda * u + v
        int256 v; // from (A chi)_y = lambda * u + v
        int256 w; // from (A chi)_x = w / lambda + z
        int256 z; // from (A chi)_x = w / lambda + z
        int256 dSq; // error in c^2 + s^2 = dSq, used to correct errors in c, s, tau, u,v,w,z calculations
        //int256 dAlpha; // normalization constant for tau(alpha)
        //int256 dBeta; // normalization constant for tau(beta)
    }

    function rateProvider0() external view returns (address);
    function rateProvider1() external view returns (address);
    function getECLPParams() external view returns (Params memory, DerivedParams memory);
}

