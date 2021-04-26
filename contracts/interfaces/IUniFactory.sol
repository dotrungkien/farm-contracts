// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IUniFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}
