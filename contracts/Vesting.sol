// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Vesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public token;
    uint256 public vestingDuration; // 1170000 blocks ~ 180 days

    struct VestingInfo {
        uint256 amount;
        uint256 startBlock;
        uint256 claimedAmount;
    }

    // user address => vestingInfo[]
    mapping(address => VestingInfo[]) private _userToVestingList;

    constructor(address _token, uint256 _vestingDuration) {
        token = IERC20(_token);
        require(_vestingDuration > 0, "Vesting: Invalid duration");

        vestingDuration = _vestingDuration;
    }

    function addVesting(address _user, uint256 _amount) external onlyOwner {
        token.safeTransferFrom(_msgSender(), address(this), _amount);
        VestingInfo memory info = VestingInfo(_amount, block.number, 0);
        _userToVestingList[_user].push(info);
    }

    function claimVesting(uint256 _index) external nonReentrant {
        _claimVestingInternal(_index);
    }

    function claimTotalVesting() external nonReentrant {
        uint256 count = _userToVestingList[_msgSender()].length;
        for (uint256 _index = 0; _index < count; _index++) {
            if (_getVestingClaimableAmount(_msgSender(), _index) > 0) {
                _claimVestingInternal(_index);
            }
        }
    }

    function _claimVestingInternal(uint256 _index) private {
        require(_index < _userToVestingList[_msgSender()].length, "Vesting: Invalid index");
        uint256 claimableAmount = _getVestingClaimableAmount(_msgSender(), _index);
        require(claimableAmount > 0, "Vesting: Nothing to claim");
        _userToVestingList[_msgSender()][_index].claimedAmount =
            _userToVestingList[_msgSender()][_index].claimedAmount +
            claimableAmount;
        require(token.transfer(_msgSender(), claimableAmount), "Vesting: transfer failed");
    }

    function _getVestingClaimableAmount(address _user, uint256 _index)
        internal
        view
        returns (uint256 claimableAmount)
    {
        VestingInfo memory info = _userToVestingList[_user][_index];
        if (block.number <= info.startBlock) return 0;
        uint256 passedBlocks = block.number - info.startBlock;

        uint256 releasedAmount;
        if (passedBlocks >= vestingDuration) {
            releasedAmount = info.amount;
        } else {
            releasedAmount = (info.amount * passedBlocks) / vestingDuration;
        }

        claimableAmount = 0;
        if (releasedAmount > info.claimedAmount) {
            claimableAmount = releasedAmount - info.claimedAmount;
        }
    }

    function getVestingTotalClaimableAmount(address _user)
        external
        view
        returns (uint256 totalClaimableAmount)
    {
        uint256 count = _userToVestingList[_user].length;
        for (uint256 _index = 0; _index < count; _index++) {
            totalClaimableAmount = totalClaimableAmount + _getVestingClaimableAmount(_user, _index);
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

    function getTotalAmountLockedByUser(address _user) external view returns (uint256) {
        uint256 count = _userToVestingList[_user].length;
        uint256 amountLocked = 0;
        for (uint256 _index = 0; _index < count; _index++) {
            amountLocked =
                amountLocked +
                _userToVestingList[_user][_index].amount -
                _userToVestingList[_user][_index].claimedAmount;
        }

        return amountLocked;
    }
}
