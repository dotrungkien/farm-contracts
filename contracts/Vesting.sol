// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IFarmFactory.sol";
import "./TransferHelper.sol";

contract Vesting is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public token;
    uint256 public totalRounds;
    uint256 public daysPerRound;

    struct VestingInfo {
        uint256 amount;
        uint256 startTime;
        uint256 claimedAmount;
    }

    // user address => vestingInfo[]
    mapping(address => VestingInfo[]) private _userToVestingList;

    constructor(
        address _token,
        uint256 _totalRounds,
        uint256 _daysPerRound
    ) {
        token = IERC20(_token);
        require(_totalRounds > 0, "Vesting: Invalid total rounds");
        require(_daysPerRound > 0, "Vesting: Invalid days per round");
        totalRounds = _totalRounds;
        daysPerRound = _daysPerRound;
    }

    function addVesting(address _user, uint256 _amount) external onlyOwner {
        token.safeTransferFrom(_msgSender(), address(this), _amount);
        VestingInfo memory info = VestingInfo(_amount, block.timestamp, 0);
        _userToVestingList[_user].push(info);
    }

    function claimVesting(uint256 _index) external {
        require(_index < _userToVestingList[_msgSender()].length, "Vesting: Invalid index");
        uint256 claimableAmount = _getVestingClaimableAmount(_msgSender(), _index);
        require(claimableAmount > 0, "Vesting: Nothing to claim");
        _userToVestingList[_msgSender()][_index].claimedAmount =
            _userToVestingList[_msgSender()][_index].claimedAmount +
            claimableAmount;
    }

    function _getVestingClaimableAmount(address _user, uint256 _index)
        internal
        view
        returns (uint256 claimableAmount)
    {
        VestingInfo memory info = _userToVestingList[_user][_index];
        if (block.timestamp < info.startTime) return 0;
        uint256 roundsPassed = ((block.timestamp - info.startTime) / 1 days) / daysPerRound;

        uint256 releasedAmount;
        if (roundsPassed >= totalRounds) {
            releasedAmount = info.amount;
        } else {
            releasedAmount = (info.amount * roundsPassed) / totalRounds;
        }

        claimableAmount = 0;
        if (releasedAmount > info.claimedAmount) {
            claimableAmount = releasedAmount - info.claimedAmount;
        }
    }

    function getVestingClaimableAmount(address _user, uint256 _index)
        external
        view
        returns (uint256)
    {
        return _getVestingClaimableAmount(_user, _index);
    }

    function getVestingsCountByUser(address _user) external view returns (uint256) {
        uint256 count = _userToVestingList[_user].length;
        return count;
    }

    function getVestingInfo(address _user, uint256 _index)
        external
        view
        returns (VestingInfo memory)
    {
        require(_index < _userToVestingList[_user].length, "Vesting: Invalid index");
        VestingInfo memory info = _userToVestingList[_user][_index];
        return info;
    }
}
