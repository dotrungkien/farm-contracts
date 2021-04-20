// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

// helper methods for interacting with ERC20 tokens that do not consistently return true/false
library TransferHelper {
  function safeApprove(
    address token,
    address to,
    uint256 value
  ) internal {
    (bool success, bytes memory data) =
      token.call(abi.encodeWithSelector(bytes4(keccak256('approve(address,uint256)')), to, value));
    require(
      success && (data.length == 0 || abi.decode(data, (bool))),
      'TransferHelper: APPROVE_FAILED'
    );
  }

  function safeTransfer(
    address token,
    address to,
    uint256 value
  ) internal {
    (bool success, bytes memory data) =
      token.call(abi.encodeWithSelector(bytes4(keccak256('transfer(address,uint256)')), to, value));
    require(
      success && (data.length == 0 || abi.decode(data, (bool))),
      'TransferHelper: TRANSFER_FAILED'
    );
  }

  function safeTransferFrom(
    address token,
    address from,
    address to,
    uint256 value
  ) internal {
    (bool success, bytes memory data) =
      token.call(
        abi.encodeWithSelector(
          bytes4(keccak256('transferFrom(address,address,uint256)')),
          from,
          to,
          value
        )
      );
    require(
      success && (data.length == 0 || abi.decode(data, (bool))),
      'TransferHelper: TRANSFER_FROM_FAILED'
    );
  }
}
