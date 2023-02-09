// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

library VaultShareLib {

    struct SplitTotal {
        uint32 split;
        uint112 max;
        uint112 total;
    }

    struct SplitBalance {
        uint32 split;
        uint112 balance;
    }

    function mint(SplitTotal storage total, SplitBalance storage balance, uint256 amount) internal {
        if (amount + total.total > total.max) {
            
        }
    }

    function balanceOf(SplitTotal storage total, SplitBalance storage balance) internal view returns (uint256) {
        uint32 unshifted = total.split - balance.split;
        return balance.balance >> unshifted;
    }

    function totalSupply(SplitTotal storage total) internal view returns (uint256) {
        return total.total;
    }

}
