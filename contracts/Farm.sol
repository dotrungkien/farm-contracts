// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./IFarmFactory.sol";
import "./TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Vesting.sol";

contract Farm {
    using SafeERC20 for IERC20;

    /// @notice information stuct on each user than stakes LP tokens.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    /// @notice all the settings for this farm in one struct
    struct FarmInfo {
        IERC20 lpToken;
        IERC20 rewardToken;
        uint256 startBlock;
        uint256 blockReward;
        uint256 bonusEndBlock;
        uint256 bonus;
        uint256 endBlock;
        uint256 lastRewardBlock; // Last block number that reward distribution occurs.
        uint256 accRewardPerShare; // Accumulated Rewards per share, times 1e12
        uint256 farmableSupply; // set in init, total amount of tokens farmable
        uint256 numFarmers;
    }

    /// @notice farm type id. Useful for back-end systems to know how to read the contract (ABI) as we plan to launch multiple farm types
    uint256 public farmType = 1;

    IFarmFactory public factory;
    address public farmGenerator;

    FarmInfo public farmInfo;
    Vesting public vesting;
    uint256 percentForVesting; // 50 equivalent to 50%

    /// @notice information on each user than stakes LP tokens
    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(address _factory, address _farmGenerator) public {
        factory = IFarmFactory(_factory);
        farmGenerator = _farmGenerator;
    }

    /**
     * @notice initialize the farming contract. This is called only once upon farm creation and the FarmGenerator ensures the farm has the correct paramaters
     */
    function init(
        IERC20 _rewardToken,
        uint256 _amount,
        IERC20 _lpToken,
        uint256 _blockReward,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _bonusEndBlock,
        uint256 _bonus,
        uint256[] memory _vestingParameters // 0: percentForVesting, 1: totalRounds, 2: daysPerRound
    ) public {
        require(msg.sender == address(farmGenerator), "Farm: FORBIDDEN");

        TransferHelper.safeTransferFrom(address(_rewardToken), msg.sender, address(this), _amount);
        farmInfo.rewardToken = _rewardToken;

        farmInfo.startBlock = _startBlock;
        farmInfo.blockReward = _blockReward;
        farmInfo.bonusEndBlock = _bonusEndBlock;
        farmInfo.bonus = _bonus;

        uint256 lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
        farmInfo.lpToken = _lpToken;
        farmInfo.lastRewardBlock = lastRewardBlock;
        farmInfo.accRewardPerShare = 0;

        farmInfo.endBlock = _endBlock;
        farmInfo.farmableSupply = _amount;

        if (_vestingParameters[0] > 0) {
            require(_vestingParameters[0] < 100, "Farm: Invalid percent for vesting");
            percentForVesting = _vestingParameters[0];
            vesting = new Vesting(
                address(_rewardToken),
                _vestingParameters[1],
                _vestingParameters[2]
            );
            _rewardToken.safeApprove(address(vesting), type(uint256).max);
        }
    }

    /**
     * @notice Gets the reward multiplier over the given _from_block until _to block
     * @param _from_block the start of the period to measure rewards for
     * @param _to the end of the period to measure rewards for
     * @return The weighted multiplier for the given period
     */
    function getMultiplier(uint256 _from_block, uint256 _to) public view returns (uint256) {
        uint256 _from = _from_block >= farmInfo.startBlock ? _from_block : farmInfo.startBlock;
        uint256 to = farmInfo.endBlock > _to ? _to : farmInfo.endBlock;
        if (to <= farmInfo.bonusEndBlock) {
            return (to - _from) * farmInfo.bonus;
        } else if (_from >= farmInfo.bonusEndBlock) {
            return to - _from;
        } else {
            return
                ((farmInfo.bonusEndBlock - _from) * farmInfo.bonus) + (to - farmInfo.bonusEndBlock);
        }
    }

    /**
     * @notice function to see accumulated balance of reward token for specified user
     * @param _user the user for whom unclaimed tokens will be shown
     * @return total amount of withdrawable reward tokens
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = farmInfo.accRewardPerShare;
        uint256 lpSupply = farmInfo.lpToken.balanceOf(address(this));
        if (block.number > farmInfo.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(farmInfo.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier * farmInfo.blockReward;
            accRewardPerShare = accRewardPerShare + ((tokenReward * 1e12) / lpSupply);
        }
        return ((user.amount * accRewardPerShare) / 1e12) - user.rewardDebt;
    }

    /**
     * @notice updates pool information to be up to date to the current block
     */
    function updatePool() public {
        if (block.number <= farmInfo.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = farmInfo.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            farmInfo.lastRewardBlock = block.number < farmInfo.endBlock
                ? block.number
                : farmInfo.endBlock;
            return;
        }
        uint256 multiplier = getMultiplier(farmInfo.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier * farmInfo.blockReward;
        farmInfo.accRewardPerShare = farmInfo.accRewardPerShare + ((tokenReward * 1e12) / lpSupply);
        farmInfo.lastRewardBlock = block.number < farmInfo.endBlock
            ? block.number
            : farmInfo.endBlock;
    }

    /**
     * @notice deposit LP token function for msg.sender
     * @param _amount the total deposit amount
     */
    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = ((user.amount * farmInfo.accRewardPerShare) / 1e12) - user.rewardDebt;

            uint256 forVesting = 0;
            if (percentForVesting > 0) {
                forVesting = (pending * percentForVesting) / 100;
                vesting.addVesting(msg.sender, forVesting);
            }

            safeRewardTransfer(msg.sender, pending - forVesting);
        }
        if (user.amount == 0 && _amount > 0) {
            factory.userEnteredFarm(msg.sender);
            farmInfo.numFarmers++;
        }
        farmInfo.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount + _amount;
        user.rewardDebt = (user.amount * farmInfo.accRewardPerShare) / 1e12;
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice withdraw LP token function for msg.sender
     * @param _amount the total withdrawable amount
     */
    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "INSUFFICIENT");
        updatePool();
        if (user.amount == _amount && _amount > 0) {
            factory.userLeftFarm(msg.sender);
            farmInfo.numFarmers--;
        }

        uint256 pending = ((user.amount * farmInfo.accRewardPerShare) / 1e12) - user.rewardDebt;

        uint256 forVesting = 0;
        if (percentForVesting > 0) {
            forVesting = (pending * percentForVesting) / 100;
            vesting.addVesting(msg.sender, forVesting);
        }

        safeRewardTransfer(msg.sender, pending - forVesting);

        user.amount = user.amount - _amount;
        user.rewardDebt = (user.amount * farmInfo.accRewardPerShare) / 1e12;
        farmInfo.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice emergency functoin to withdraw LP tokens and forego harvest rewards. Important to protect users LP tokens
     */
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        farmInfo.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        if (user.amount > 0) {
            factory.userLeftFarm(msg.sender);
            farmInfo.numFarmers--;
        }
        user.amount = 0;
        user.rewardDebt = 0;
    }

    /**
     * @notice Safe reward transfer function, just in case a rounding error causes pool to not have enough reward tokens
     * @param _to the user address to transfer tokens to
     * @param _amount the total amount of tokens to transfer
     */
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBal = farmInfo.rewardToken.balanceOf(address(this));
        if (_amount > rewardBal) {
            farmInfo.rewardToken.transfer(_to, rewardBal);
        } else {
            farmInfo.rewardToken.transfer(_to, _amount);
        }
    }
}
