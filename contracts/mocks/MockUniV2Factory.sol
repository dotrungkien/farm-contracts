// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract MockUniV2Factory {
  mapping(address => mapping(address => address)) public getPair;

  function setPair(
    address _token0,
    address _token1,
    address _pair
  ) external {
    getPair[_token0][_token1] = _pair;
    getPair[_token1][_token0] = _pair;
  }
}
