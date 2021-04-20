// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract MockUniV2Pair is ERC20, Ownable {
  address public token0;
  address public token1;

  constructor(
    string memory name,
    string memory symbol,
    address _token0,
    address _token1
  ) ERC20(name, symbol) {
    token0 = _token0;
    token1 = _token1;
  }

  function mint(address to, uint256 amount) external onlyOwner {
    _mint(to, amount);
  }
}
