// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../interfaces/IERC20.sol";
import "./Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    /**
     * @dev Transfer `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to `transferFrom`, and can be used to e.g.
     * implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a `Transfer` event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        bool success = token.transferFrom(from, to, amount);
        require(success, "SafeERC20: transferFrom failed");
    }

    /**
     * @dev Transfer `amount` of tokens from the caller to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a `Transfer` event.
     */
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        bool success = token.transfer(to, amount);
        require(success, "SafeERC20: transfer failed");
    }

    /**
     * @dev Approve `spender` to transfer `amount` of tokens from the caller.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits an `Approval` event.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 amount
    ) internal {
        bool success = token.approve(spender, amount);
        require(success, "SafeERC20: approve failed");
    }

    /**
     * @dev Increase the allowance granted to `spender` by the caller.
     *
     * This is an alternative to `approve` that can be used as a mitigation for
     * problems described in `IERC20.approve`.
     *
     * Emits an `Approval` event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 addedValue
    ) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        bool success = token.approve(spender, currentAllowance + addedValue);
        require(success, "SafeERC20: increaseAllowance failed");
    }

    /**
     * @dev Decrease the allowance granted to `spender` by the caller.
     *
     * This is an alternative to `approve` that can be used as a mitigation for
     * problems described in `IERC20.approve`.
     *
     * Emits an `Approval` event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 subtractedValue
    ) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        require(currentAllowance >= subtractedValue, "SafeERC20: decreased allowance below zero");
        bool success = token.approve(spender, currentAllowance - subtractedValue);
        require(success, "SafeERC20: decreaseAllowance failed");
    }

}
