// SPDX-License-Identifier: GPL-3.0

// Ideally this contract should not be interacted with directly. Use our front end Dapp to create a farm
// to ensure the most effeicient amount of tokens are sent to the contract
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./Farm.sol";
import "./TransferHelper.sol";
import "./interfaces/IERCBurn.sol";
import "./interfaces/IFarmFactory.sol";
import "./interfaces/IUniFactory.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract FarmGenerator is Ownable {
    IFarmFactory public factory;
    IUniFactory public uniswapFactory;

    address payable private _devaddr;

    struct FarmParameters {
        uint256 bonusBlocks;
        uint256 totalBonusReward;
        uint256 numBlocks;
        uint256 endBlock;
        uint256 requiredAmount;
    }

    constructor(IFarmFactory _factory, IUniFactory _uniswapFactory) {
        factory = _factory;
        _devaddr = payable(msg.sender);
        uniswapFactory = _uniswapFactory;
    }

    function setDev(address payable devaddr_) public onlyOwner {
        _devaddr = devaddr_;
    }

    /**
     * @notice Determine the endBlock based on inputs. Used on the front end to show the exact settings the Farm contract will be deployed with
     */
    function determineEndBlock(
        uint256 _amount,
        uint256 _blockReward,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _bonus
    ) public pure returns (uint256, uint256) {
        FarmParameters memory params;
        params.bonusBlocks = _bonusEndBlock - _startBlock;
        params.totalBonusReward = params.bonusBlocks * _bonus * _blockReward;
        params.numBlocks = (_amount - params.totalBonusReward) / (_blockReward);
        params.endBlock = params.numBlocks + params.bonusBlocks + _startBlock;

        uint256 nonBonusBlocks = params.endBlock - _bonusEndBlock;
        uint256 effectiveBlocks = params.bonusBlocks * _bonus + nonBonusBlocks;
        uint256 requiredAmount = _blockReward * effectiveBlocks;
        return (params.endBlock, requiredAmount);
    }

    /**
     * @notice Determine the blockReward based on inputs specifying an end date. Used on the front end to show the exact settings the Farm contract will be deployed with
     */
    function determineBlockReward(
        uint256 _amount,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _bonus,
        uint256 _endBlock
    ) public pure returns (uint256, uint256) {
        uint256 bonusBlocks = _bonusEndBlock - _startBlock;
        uint256 nonBonusBlocks = _endBlock - _bonusEndBlock;
        uint256 effectiveBlocks = bonusBlocks * _bonus + nonBonusBlocks;
        uint256 blockReward = _amount / effectiveBlocks;
        uint256 requiredAmount = blockReward * effectiveBlocks;
        return (blockReward, requiredAmount);
    }

    /**
     * @notice Creates a new Farm contract and registers it in the FarmFactory.sol. All farming rewards are locked in the Farm Contract
     */
    function createFarm(
        IERC20 _rewardToken,
        uint256 _amount,
        IERC20 _lpToken,
        uint256 _blockReward,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _bonus,
        uint256[] memory _vestingParameters // 0: percentForVesting, 1: totalRounds, 2: daysPerRound
    ) public payable returns (address) {
        require(_startBlock > block.number, "START"); // ideally at least 24 hours more to give farmers time
        require(_bonus > 0, "BONUS");
        require(address(_rewardToken) != address(0), "TOKEN");
        require(_blockReward > 1000, "BR"); // minimum 1000 divisibility per block reward
        require(_vestingParameters.length == 3, "Farm Generator: Invalid vesting parameters");

        // ensure this pair is on uniswap by querying the factory
        IUniswapV2Pair lpair = IUniswapV2Pair(address(_lpToken));
        address factoryPairAddress = uniswapFactory.getPair(lpair.token0(), lpair.token1());
        require(factoryPairAddress == address(_lpToken), "This pair is not on uniswap");

        FarmParameters memory params;
        (params.endBlock, params.requiredAmount) = determineEndBlock(
            _amount,
            _blockReward,
            _startBlock,
            _bonusEndBlock,
            _bonus
        );

        TransferHelper.safeTransferFrom(
            address(_rewardToken),
            address(msg.sender),
            address(this),
            params.requiredAmount
        );
        Farm newFarm = new Farm(address(factory), address(this));
        TransferHelper.safeApprove(address(_rewardToken), address(newFarm), params.requiredAmount);
        newFarm.init(
            _rewardToken,
            params.requiredAmount,
            _lpToken,
            _blockReward,
            _startBlock,
            params.endBlock,
            _bonusEndBlock,
            _bonus,
            _vestingParameters
        );

        factory.addFarm(address(newFarm));
        return (address(newFarm));
    }
}
