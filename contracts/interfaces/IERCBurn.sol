// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IERCBurn {
    function burn(uint256 _amount) external;

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external returns (uint256);
}
