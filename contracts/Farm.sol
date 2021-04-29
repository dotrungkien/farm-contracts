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
    uint256 public rewardPerBlock;
    uint256 public lastRewardBlock;
    uint256 public accRewardPerShare;
    uint256 public farmerCount;
    bool public isActive;

    uint256 public firstCycleRate;
    uint256 public initRate;
    uint256 public reducingRate; // 95 equivalent to 95%
    uint256 public reducingCycle; // 195000 equivalent 195000 block

    IFarmFactory public factory;
    address public farmGenerator;

    Vesting public vesting;
    uint256 public percentForVesting; // 50 equivalent to 50%

    /// @notice information on each user than stakes LP tokens
    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    modifier onlyFarmGeneratorOwner() {
        require(msg.sender == Ownable(farmGenerator).owner(), "Farm: FORBIDDEN");
        _;
    }

    modifier mustActive() {
        require(isActive == true, "Farm: Not active");
        _;
    }

    constructor(address _factory, address _farmGenerator) {
        factory = IFarmFactory(_factory);
        farmGenerator = _farmGenerator;
    }

    /**
     * @notice initialize the farming contract. This is called only once upon farm creation and the FarmGenerator ensures the farm has the correct paramaters
     */
    function init(
        IERC20 _rewardToken,
        IERC20 _lpToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256[] memory _rateParameters, // 0: firstCycleRate , 1: initRate, 2: reducingRate, 3: reducingCycle
        uint256[] memory _vestingParameters // 0: percentForVesting, 1: vestingDuration
    ) public {
        require(msg.sender == address(farmGenerator), "Farm: FORBIDDEN");
        require(address(_rewardToken) != address(0), "Farm: Invalid reward token");
        require(_rewardPerBlock > 1000, "Farm: Invalid block reward"); // minimum 1000 divisibility per block reward
        require(_startBlock > block.number, "Farm: Invalid start block"); // ideally at least 24 hours more to give farmers time
        require(_vestingParameters[0] <= 100, "Farm: Invalid percent for vesting");
        require(_rateParameters[0] > 0, "Farm: Invalid first cycle rate");
        require(_rateParameters[1] > 0, "Farm: Invalid initial rate");
        require(_rateParameters[2] > 0 && _rateParameters[1] < 100, "Farm: Invalid reducing rate");
        require(_rateParameters[3] > 0, "Farm: Invalid reducing cycle");

        rewardToken = _rewardToken;
        startBlock = _startBlock;
        rewardPerBlock = _rewardPerBlock;
        firstCycleRate = _rateParameters[0];
        initRate = _rateParameters[1];
        reducingRate = _rateParameters[2];
        reducingCycle = _rateParameters[3];
        isActive = true;

        uint256 _lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
        lpToken = _lpToken;
        lastRewardBlock = _lastRewardBlock;
        accRewardPerShare = 0;

        if (_vestingParameters[0] > 0) {
            percentForVesting = _vestingParameters[0];
            vesting = new Vesting(address(_rewardToken), _vestingParameters[1]);
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
        return _getMultiplierFromStart(_toBlock) - _getMultiplierFromStart(_fromBlock);
    }

    function _getMultiplierFromStart(uint256 _block) internal view returns (uint256) {
        uint256 roundPassed = (_block - startBlock) / reducingCycle;

        if (roundPassed == 0) {
            return (_block - startBlock) * firstCycleRate * 1e12;
        } else {
            uint256 multiplier = reducingCycle * firstCycleRate * 1e12;
            uint256 i = 0;
            for (i = 0; i < roundPassed - 1; i++) {
                multiplier =
                    multiplier +
                    ((1e12 * initRate * reducingRate**i) / 100**i) *
                    reducingCycle;
            }

            if ((_block - startBlock) % reducingCycle > 0) {
                multiplier =
                    multiplier +
                    ((1e12 * initRate * reducingRate**i) / 100**i) *
                    ((_block - startBlock) % reducingCycle);
            }

            return multiplier;
        }
    }

    /**
     * @notice function to see accumulated balance of reward token for specified user
     * @param _user the user for whom unclaimed tokens will be shown
     * @return total amount of withdrawable reward tokens
     */
    function pendingReward(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        uint256 _lpSupply = lpToken.balanceOf(address(this));
        if (block.number > lastRewardBlock && _lpSupply != 0 && isActive == true) {
            uint256 _multiplier = getMultiplier(lastRewardBlock, block.number);
            uint256 _tokenReward = (_multiplier * rewardPerBlock) / 1e12;
            _accRewardPerShare = _accRewardPerShare + ((_tokenReward * 1e12) / _lpSupply);
        }
        return ((user.amount * _accRewardPerShare) / 1e12) - user.rewardDebt;
    }

    /**
     * @notice updates pool information to be up to date to the current block
     */
    function updatePool() public mustActive {
        if (block.number <= lastRewardBlock) {
            return;
        }
        uint256 _lpSupply = lpToken.balanceOf(address(this));
        if (_lpSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 _multiplier = getMultiplier(lastRewardBlock, block.number);
        uint256 _tokenReward = (_multiplier * rewardPerBlock) / 1e12;
        accRewardPerShare = accRewardPerShare + ((_tokenReward * 1e12) / _lpSupply);
        lastRewardBlock = block.number;
    }

    /**
     * @notice deposit LP token function for msg.sender
     * @param _amount the total deposit amount
     */
    function deposit(uint256 _amount) public mustActive {
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

        if (isActive == true) {
            updatePool();
        }

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
    ) external onlyFarmGeneratorOwner {
        require(address(lpToken) != tokenToRescue, "Farm: Cannot claim token held by the contract");

        IERC20(tokenToRescue).safeTransfer(to, amount);
    }

    function updateReducingRate(uint256 _reducingRate) external onlyFarmGeneratorOwner mustActive {
        reducingRate = _reducingRate;
    }

    function forceEnd() external onlyFarmGeneratorOwner mustActive {
        updatePool();
        isActive = false;
    }
}
