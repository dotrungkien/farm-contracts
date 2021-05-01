// SPDX-License-Identifier: GPL-3.0

// Ideally this contract should not be interacted with directly. Use our front end Dapp to create a farm
// to ensure the most effeicient amount of tokens are sent to the contract
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./Farm.sol";
import "./interfaces/IERCBurn.sol";
import "./interfaces/IFarmFactory.sol";
import "./interfaces/IPancakeFactory.sol";
import "./interfaces/IPancakePair.sol";

contract FarmGenerator is Ownable {
    using SafeERC20 for IERC20;
    IFarmFactory public factory;
    IPancakeFactory public uniswapFactory;

    address payable private _devaddr;

    constructor(IFarmFactory _factory, IPancakeFactory _uniswapFactory) {
        factory = _factory;
        _devaddr = payable(msg.sender);
        uniswapFactory = _uniswapFactory;
    }

    function setDev(address payable devaddr_) public onlyOwner {
        _devaddr = devaddr_;
    }

    /**
     * @notice Creates a new Farm contract and registers it in the FarmFactory.sol. All farming rewards are locked in the Farm Contract
     */
    function createFarm(
        IERC20 _rewardToken,
        uint256 _amount,
        IERC20 _lpToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        address _owner,
        uint256[] memory _rateParameters, // 0: firstCycleRate 1: initRate, 2: reducingRate, 3: reducingCycle
        uint256[] memory _vestingParameters // 0: percentForVesting, 1: vestingDuration
    ) public onlyOwner returns (address) {
        require(_rateParameters.length == 4, "Farm Generator: Invalid vesting parameters");
        require(_vestingParameters.length == 2, "Farm Generator: Invalid vesting parameters");
        IPancakePair lpair = IPancakePair(address(_lpToken));
        address factoryPairAddress = uniswapFactory.getPair(lpair.token0(), lpair.token1());
        require(factoryPairAddress == address(_lpToken), "This pair is not on uniswap");

        Farm newFarm = new Farm(address(factory), address(this));

        _rewardToken.safeTransferFrom(_msgSender(), address(newFarm), _amount);

        newFarm.init(
            _rewardToken,
            _lpToken,
            _rewardPerBlock,
            _startBlock,
            _rateParameters,
            _vestingParameters,
            _owner
        );

        factory.addFarm(address(newFarm));
        return (address(newFarm));
    }
}
