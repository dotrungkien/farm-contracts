// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IFarmFactory {
    function userEnteredFarm(address _user) external;

    function userLeftFarm(address _user) external;

    function registerFarm(address _farmAddress) external;
}
