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

    struct FeeStruct {
        IERCBurn gasToken;
        bool useGasToken; // set to false to waive the gas fee
        uint256 gasFee; // the total amount of gas tokens to be burnt (if used)
        uint256 ethFee; // Small eth fee to prevent spam on the platform
        uint256 tokenFee; // Divided by 1000, fee on farm rewards
    }

    FeeStruct public gFees;

    struct FarmParameters {
        uint256 fee;
        uint256 amountMinusFee;
        uint256 bonusBlocks;
        uint256 totalBonusReward;
        uint256 numBlocks;
        uint256 endBlock;
        uint256 requiredAmount;
        uint256 amountFee;
    }

    constructor(IFarmFactory _factory, IUniFactory _uniswapFactory) {
        factory = _factory;
        _devaddr = payable(msg.sender);
        gFees.useGasToken = false;
        gFees.gasFee = 1 * (10**18);
        gFees.ethFee = 2e17;
        gFees.tokenFee = 10; // 1%
        uniswapFactory = _uniswapFactory;
    }

    /**
     * @notice Below are self descriptive gas fee and general settings functions
     */
    function setGasToken(IERCBurn _gasToken) public onlyOwner {
        gFees.gasToken = _gasToken;
    }

    function setGasFee(uint256 _amount) public onlyOwner {
        gFees.gasFee = _amount;
    }

    function setEthFee(uint256 _amount) public onlyOwner {
        gFees.ethFee = _amount;
    }

    function setTokenFee(uint256 _amount) public onlyOwner {
        gFees.tokenFee = _amount;
    }

    function setRequireGasToken(bool _useGasToken) public onlyOwner {
        gFees.useGasToken = _useGasToken;
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
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        FarmParameters memory params;
        params.fee = (_amount * gFees.tokenFee) / 1000;
        params.amountMinusFee = _amount - params.fee;
        params.bonusBlocks = _bonusEndBlock - _startBlock;
        params.totalBonusReward = params.bonusBlocks * _bonus * _blockReward;
        params.numBlocks = (params.amountMinusFee - params.totalBonusReward) / (_blockReward);
        params.endBlock = params.numBlocks + params.bonusBlocks + _startBlock;

        uint256 nonBonusBlocks = params.endBlock - _bonusEndBlock;
        uint256 effectiveBlocks = params.bonusBlocks * _bonus + nonBonusBlocks;
        uint256 requiredAmount = _blockReward * effectiveBlocks;
        return (params.endBlock, requiredAmount, (requiredAmount * gFees.tokenFee) / 1000);
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
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 fee = (_amount * gFees.tokenFee) / 1000;
        uint256 amountMinusFee = _amount - fee;
        uint256 bonusBlocks = _bonusEndBlock - _startBlock;
        uint256 nonBonusBlocks = _endBlock - _bonusEndBlock;
        uint256 effectiveBlocks = bonusBlocks * _bonus + nonBonusBlocks;
        uint256 blockReward = amountMinusFee / effectiveBlocks;
        uint256 requiredAmount = blockReward * effectiveBlocks;
        return (blockReward, requiredAmount, (requiredAmount * gFees.tokenFee) / 1000);
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
        (params.endBlock, params.requiredAmount, params.amountFee) = determineEndBlock(
            _amount,
            _blockReward,
            _startBlock,
            _bonusEndBlock,
            _bonus
        );

        require(msg.value == gFees.ethFee, "Fee not met");
        _devaddr.transfer(msg.value);

        if (gFees.useGasToken) {
            TransferHelper.safeTransferFrom(
                address(gFees.gasToken),
                address(msg.sender),
                address(this),
                gFees.gasFee
            );
            gFees.gasToken.burn(gFees.gasFee);
        }

        TransferHelper.safeTransferFrom(
            address(_rewardToken),
            address(msg.sender),
            address(this),
            params.requiredAmount + params.amountFee
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

        TransferHelper.safeTransfer(address(_rewardToken), _devaddr, params.amountFee);
        factory.registerFarm(address(newFarm));
        return (address(newFarm));
    }
}
