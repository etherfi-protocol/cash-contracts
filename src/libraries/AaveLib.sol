// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEtherFiCashAaveV3Adapter} from "../interfaces/IEtherFiCashAaveV3Adapter.sol";
library AaveLib {
    error InvalidMarketOperationType();

    enum MarketOperationType {
        Supply,
        Borrow,
        Repay,
        Withdraw,
        SupplyAndBorrow
    }

    function aaveOperation(
        address aaveV3Adapter,
        uint8 marketOperationType,
        bytes calldata data
    ) internal {
        if (marketOperationType == uint8(MarketOperationType.Supply)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            supplyOnAave(aaveV3Adapter, token, amount);
        } else if (marketOperationType == uint8(MarketOperationType.Borrow)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            borrowFromAave(aaveV3Adapter, token, amount);
        } else if (marketOperationType == uint8(MarketOperationType.Repay)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            repayOnAave(aaveV3Adapter, token, amount);
        } else if (marketOperationType == uint8(MarketOperationType.Withdraw)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            withdrawFromAave(aaveV3Adapter, token, amount);
        } else if (
            marketOperationType == uint8(MarketOperationType.SupplyAndBorrow)
        ) {
            (
                address tokenToSupply,
                uint256 amountToSupply,
                address tokenToBorrow,
                uint256 amountToBorrow
            ) = abi.decode(data, (address, uint256, address, uint256));
            supplyAndBorrowOnAave(
                aaveV3Adapter,
                tokenToSupply,
                amountToSupply,
                tokenToBorrow,
                amountToBorrow
            );
        } else revert InvalidMarketOperationType();
    }

    function supplyAndBorrowOnAave(
        address aaveV3Adapter,
        address tokenToSupply,
        uint256 amountToSupply,
        address tokenToBorrow,
        uint256 amountToBorrow
    ) internal {
        delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.process.selector,
                tokenToSupply,
                amountToSupply,
                tokenToBorrow,
                amountToBorrow
            )
        );
    }

    function supplyOnAave(
        address aaveV3Adapter,
        address token,
        uint256 amount
    ) internal {
        delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.supply.selector,
                token,
                amount
            )
        );
    }

    function borrowFromAave(
        address aaveV3Adapter,
        address token,
        uint256 amount
    ) internal {
        delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.borrow.selector,
                token,
                amount
            )
        );
    }

    function repayOnAave(
        address aaveV3Adapter,
        address token,
        uint256 amount
    ) internal {
        delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.repay.selector,
                token,
                amount
            )
        );
    }

    function withdrawFromAave(
        address aaveV3Adapter,
        address token,
        uint256 amount
    ) internal {
        delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.withdraw.selector,
                token,
                amount
            )
        );
    }

    function delegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory result) {
        require(target != address(this), "delegatecall to self");

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Perform delegatecall to the target contract
            let success := delegatecall(
                gas(),
                target,
                add(data, 0x20),
                mload(data),
                0,
                0
            )

            // Get the size of the returned data
            let size := returndatasize()

            // Allocate memory for the return data
            result := mload(0x40)

            // Set the length of the return data
            mstore(result, size)

            // Copy the return data to the allocated memory
            returndatacopy(add(result, 0x20), 0, size)

            // Update the free memory pointer
            mstore(0x40, add(result, add(0x20, size)))

            if iszero(success) {
                revert(result, returndatasize())
            }
        }
    }
}
