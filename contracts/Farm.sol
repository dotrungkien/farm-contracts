// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IFarmFactory.sol";
import "./TransferHelper.sol";
import "./Vesting.sol";

contract Farm {
    using SafeERC20 for IERC20;

    /// @notice information stuct on each user than stakes LP tokens.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    IERC20 public lpToken;
    IERC20 public rewardToken;
    uint256 public startBlock;
    uint256 public blockReward;
    uint256 public bonusEndBlock;
    uint256 public bonusRate;
    uint256 public endBlock;
    uint256 public lastRewardBlock;
    uint256 public accRewardPerShare;
    uint256 public farmerCount;

    IFarmFactory public factory;
    address public farmGenerator;

    Vesting public vesting;
    uint256 public percentForVesting; // 50 equivalent to 50%

    /// @notice information on each user than stakes LP tokens
    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(address _factory, address _farmGenerator) {
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
        uint256 _bonusRate,
        uint256[] memory _vestingParameters // 0: percentForVesting, 1: totalRounds, 2: daysPerRound
    ) public {
        require(msg.sender == address(farmGenerator), "Farm: FORBIDDEN");
        require(_vestingParameters[0] <= 100, "Farm: Invalid percent for vesting");

        TransferHelper.safeTransferFrom(address(_rewardToken), msg.sender, address(this), _amount);

        rewardToken = _rewardToken;
        startBlock = _startBlock;
        blockReward = _blockReward;
        bonusEndBlock = _bonusEndBlock;
        bonusRate = _bonusRate;

        uint256 _lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
        lpToken = _lpToken;
        lastRewardBlock = _lastRewardBlock;
        accRewardPerShare = 0;

        endBlock = _endBlock;

        if (_vestingParameters[0] > 0) {
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
     * @notice Gets the reward multiplier over the given _fromBlock until _to block
     * @param _fromBlock the start of the period to measure rewards for
     * @param _toBlock the end of the period to measure rewards for
     * @return The weighted multiplier for the given period
     */
    function getMultiplier(uint256 _fromBlock, uint256 _toBlock) public view returns (uint256) {
        uint256 _from = _fromBlock >= startBlock ? _fromBlock : startBlock;
        uint256 _to = endBlock > _toBlock ? _toBlock : endBlock;
        if (_to <= bonusEndBlock) {
            return (_to - _from) * bonusRate;
        } else if (_from >= bonusEndBlock) {
            return _to - _from;
        } else {
            return ((bonusEndBlock - _from) * bonusRate) + (_to - bonusEndBlock);
        }
    }

    /**
     * @notice function to see accumulated balance of reward token for specified user
     * @param _user the user for whom unclaimed tokens will be shown
     * @return total amount of withdrawable reward tokens
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        uint256 _lpSupply = lpToken.balanceOf(address(this));
        if (block.number > lastRewardBlock && _lpSupply != 0) {
            uint256 _multiplier = getMultiplier(lastRewardBlock, block.number);
            uint256 _tokenReward = _multiplier * blockReward;
            _accRewardPerShare = _accRewardPerShare + ((_tokenReward * 1e12) / _lpSupply);
        }
        return ((user.amount * _accRewardPerShare) / 1e12) - user.rewardDebt;
    }

    /**
     * @notice updates pool information to be up to date to the current block
     */
    function updatePool() public {
        if (block.number <= lastRewardBlock) {
            return;
        }
        uint256 _lpSupply = lpToken.balanceOf(address(this));
        if (_lpSupply == 0) {
            lastRewardBlock = block.number < endBlock ? block.number : endBlock;
            return;
        }
        uint256 _multiplier = getMultiplier(lastRewardBlock, block.number);
        uint256 _tokenReward = _multiplier * blockReward;
        accRewardPerShare = accRewardPerShare + ((_tokenReward * 1e12) / _lpSupply);
        lastRewardBlock = block.number < endBlock ? block.number : endBlock;
    }

    /**
     * @notice deposit LP token function for msg.sender
     * @param _amount the total deposit amount
     */
    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 _pending = ((user.amount * accRewardPerShare) / 1e12) - user.rewardDebt;

            uint256 _forVesting = 0;
            if (percentForVesting > 0) {
                _forVesting = (_pending * percentForVesting) / 100;
                vesting.addVesting(msg.sender, _forVesting);
            }

            _safeRewardTransfer(msg.sender, _pending - _forVesting);
        }
        if (user.amount == 0 && _amount > 0) {
            factory.userEnteredFarm(msg.sender);
            farmerCount++;
        }
        lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        user.amount = user.amount + _amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;
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
            farmerCount--;
        }

        uint256 _pending = ((user.amount * accRewardPerShare) / 1e12) - user.rewardDebt;

        uint256 _forVesting = 0;
        if (percentForVesting > 0) {
            _forVesting = (_pending * percentForVesting) / 100;
            vesting.addVesting(msg.sender, _forVesting);
        }

        _safeRewardTransfer(msg.sender, _pending - _forVesting);

        user.amount = user.amount - _amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;
        lpToken.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice emergency functoin to withdraw LP tokens and forego harvest rewards. Important to protect users LP tokens
     */
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        lpToken.safeTransfer(msg.sender, user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        if (user.amount > 0) {
            factory.userLeftFarm(msg.sender);
            farmerCount--;
        }
        user.amount = 0;
        user.rewardDebt = 0;
    }

    /**
     * @notice Safe reward transfer function, just in case a rounding error causes pool to not have enough reward tokens
     * @param _to the user address to transfer tokens to
     * @param _amount the total amount of tokens to transfer
     */
    function _safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 _rewardBal = rewardToken.balanceOf(address(this));
        if (_amount > _rewardBal) {
            rewardToken.transfer(_to, _rewardBal);
        } else {
            rewardToken.transfer(_to, _amount);
        }
    }

    function rescueFunds(
        address tokenToRescue,
        address to,
        uint256 amount
    ) external {
        require(msg.sender == Ownable(farmGenerator).owner(), "Farm: FORBIDDEN");
        require(
            address(lpToken) != tokenToRescue && address(rewardToken) != tokenToRescue,
            "Farm: Cannot claim token held by the contract"
        );

        IERC20(tokenToRescue).safeTransfer(to, amount);
    }
}
