// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-interfaces/contracts/pool-linear/IBeefyVault.sol";

import "../LinearPool.sol";

contract BeefyLinearPool is LinearPool {
    IBeefyVault private immutable _tokenVault;

    uint256 private immutable _balanceScaleFactor;

    struct ConstructorArgs {
        IVault vault;
        string name;
        string symbol;
        IERC20 mainToken;
        IERC20 wrappedToken;
        address assetManager;
        uint256 upperTarget;
        uint256 swapFeePercentage;
        uint256 pauseWindowDuration;
        uint256 bufferPeriodDuration;
        address owner;
    }

    constructor(ConstructorArgs memory args)
        LinearPool(
            args.vault,
            args.name,
            args.symbol,
            args.mainToken,
            args.wrappedToken,
            args.upperTarget,
            _toAssetManagerArray(args),
            args.swapFeePercentage,
            args.pauseWindowDuration,
            args.bufferPeriodDuration,
            args.owner
        )
    {
        IBeefyVault tokenVault = IBeefyVault(address(args.wrappedToken));

        _tokenVault = tokenVault;
        address want = tokenVault.want();

        // Beefy vault tokens are always 18 decimal places, but are stored in the precision of the mainToken
        // ie: If ppfs === 1e18, 1 USDC === 0.000_000_000_001_000_000 mooUSDC
        // ie: If ppfs === 1e18, 1 DAI === 1 mooDAI
        // ie: If ppfs === 1e18, 1 WBTC === 0.000_000_000_100_000_000 mooWBTC
        // -----------
        // Internally, the LinearPool scales all balances and rates up to 18 decimal places, meaning that 1 USDC is
        // represented as 1e18 by the LinearPool. Since the mooUSDC is already 18 decimals,
        // but in a different representation, we need to account for that in our wrappedTokenRate.
        // Since we only accept tokens with <= 18 decimals, we know the smallest this can be is 10^0 === 1
        _balanceScaleFactor = 10**(SafeMath.add(18, SafeMath.sub(18, ERC20(want).decimals())));

        _require(address(args.mainToken) == want, Errors.TOKENS_MISMATCH);
    }

    function _toAssetManagerArray(ConstructorArgs memory args) private pure returns (address[] memory) {
        // We assign the same asset manager to both the main and wrapped tokens.
        address[] memory assetManagers = new address[](2);
        assetManagers[0] = args.assetManager;
        assetManagers[1] = args.assetManager;

        return assetManagers;
    }

    function _getWrappedTokenRate() internal view override returns (uint256) {
        uint256 vaultTotalSupply = _tokenVault.totalSupply();
        return vaultTotalSupply == 0 
            ? _balanceScaleFactor 
            : _tokenVault.balance() * _balanceScaleFactor / vaultTotalSupply;
    }
}
