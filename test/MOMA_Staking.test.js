const { ethers } = require('hardhat');
const { expect } = require('chai');
const { time } = require('@openzeppelin/test-helpers');

describe('Test Farming', async () => {
  let farmFactory, farmGenerator, farm, uniPair, uniFactory, moma, weth;
  let deployer, alice, bob, jack;
  let startBlock;

  let aliceMomaBeforeBalance = '1000000000000000000000000';
  let bobLPBeforeBalance = '1000000000000000000';
  let jackLPBeforeBalance = '1000000000000000000';

  let amountToFarm = '2000000000000000000000';
  let rewardPerBlock = '2000000000000000000';

  let firstCycleRate = 6;
  let initRate = 3;
  let reducingRate = 95;
  let reducingCycle = 195000;

  let percentForVesting = 50;
  let vestingDuration = 195000;

  beforeEach(async () => {
    [deployer, alice, bob, jack] = await ethers.getSigners();

    let TestERC20 = await ethers.getContractFactory('TestERC20');
    moma = await TestERC20.connect(deployer).deploy('MOchi MArket Token', 'MOMA');

    let WETH9 = await ethers.getContractFactory('WETH9');
    weth = await WETH9.connect(deployer).deploy();

    let MockUniV2Pair = await ethers.getContractFactory('MockUniV2Pair');
    uniPair = await MockUniV2Pair.connect(deployer).deploy(
      'MOMA-WETH LP',
      'MOMA-WETH',
      moma.address,
      weth.address
    );

    let MockUniV2Factory = await ethers.getContractFactory('MockUniV2Factory');
    uniFactory = await MockUniV2Factory.connect(deployer).deploy();
    await uniFactory.connect(deployer).setPair(moma.address, weth.address, uniPair.address);

    let FarmFactory = await ethers.getContractFactory('FarmFactory');
    farmFactory = await FarmFactory.connect(deployer).deploy();

    let FarmGenerator = await ethers.getContractFactory('FarmGenerator');
    farmGenerator = await FarmGenerator.connect(deployer).deploy(
      farmFactory.address,
      uniFactory.address
    );

    await farmFactory.connect(deployer).adminAllowFarmGenerator(farmGenerator.address, true);

    startBlock = parseInt(await time.latestBlock()) + 100;

    await moma.connect(deployer).mint(deployer.address, aliceMomaBeforeBalance);
    await moma.connect(deployer).approve(farmGenerator.address, aliceMomaBeforeBalance);
    await farmGenerator.connect(deployer).createFarm(
      moma.address,
      amountToFarm, // 2000 MOMA
      uniPair.address,
      rewardPerBlock, // 2 MOMA / block
      startBlock,
      [firstCycleRate, initRate, reducingRate, reducingCycle],
      [percentForVesting, vestingDuration]
    );

    farm = await ethers.getContractAt('Farm', await farmFactory.farmAtIndex('0'));
  });

  it('All setup successfully', async () => {
    console.log('LP token: ', await farm.lpToken());
    console.log('Reward token: ', await farm.rewardToken());
    console.log('Start block: ', parseInt(await farm.startBlock()));
    console.log('Reward per block: ', parseInt(await farm.rewardPerBlock()));
    console.log('Last reward block: ', parseInt(await farm.lastRewardBlock()));
    console.log('Accurate reward per share: ', parseInt(await farm.accRewardPerShare()));
    console.log('Farmer count: ', parseInt(await farm.farmerCount()));
    console.log('Initial rate: ', parseInt(await farm.initRate()));
    console.log('Reducing rate: ', parseInt(await farm.reducingRate()));
    console.log('Reducing cycle: ', parseInt(await farm.reducingCycle()));
    console.log('Farm factory: ', await farm.factory());
    console.log('Farm generator: ', await farm.farmGenerator());
    console.log('Vesting : ', await farm.vesting());
    console.log('Percent for vesting : ', parseInt(await farm.percentForVesting()));
  });

  it('Check multiplier', async () => {
    expect(parseInt(await farm.getMultiplier(startBlock, startBlock))).to.be.equal(0);

    expect(parseInt(await farm.getMultiplier(startBlock, startBlock + 1))).to.be.equal(
      firstCycleRate * 1e12
    );
    expect(parseInt(await farm.getMultiplier(startBlock, startBlock + 194999))).to.be.equal(
      firstCycleRate * 1e12 * 194999
    );
    expect(parseInt(await farm.getMultiplier(startBlock, startBlock + 195000))).to.be.equal(
      firstCycleRate * 1e12 * 195000
    );

    expect(parseInt(await farm.getMultiplier(startBlock, startBlock + 195100))).to.be.equal(
      firstCycleRate * 1e12 * 195000 + 100 * initRate * 1e12
    );

    expect(parseInt(await farm.getMultiplier(startBlock, startBlock + 390000))).to.be.equal(
      firstCycleRate * 1e12 * 195000 + 195000 * initRate * 1e12
    );

    expect(parseInt(await farm.getMultiplier(startBlock, startBlock + 391000))).to.be.equal(
      firstCycleRate * 1e12 * 195000 +
        195000 * initRate * 1e12 +
        (1000 * 1e12 * initRate * reducingRate) / 100
    );

    expect(
      parseInt(await farm.getMultiplier(startBlock + 195001, startBlock + 391000))
    ).to.be.equal(
      initRate * 1e12 * (390000 - 195001) + (1000 * 1e12 * initRate * reducingRate) / 100
    );

    expect(
      parseInt(await farm.getMultiplier(startBlock + 195001, startBlock + 391000))
    ).to.be.equal(
      parseInt(await farm.getMultiplier(startBlock, startBlock + 391000)) -
        parseInt(await farm.getMultiplier(startBlock, startBlock + 195001))
    );
  });

  it('Bob deposit successfully first and only bob in pool', async () => {
    await uniPair.connect(deployer).mint(bob.address, bobLPBeforeBalance);
    await uniPair.connect(bob).approve(farm.address, bobLPBeforeBalance);
    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 1);
    expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
      firstCycleRate * parseInt(rewardPerBlock)
    );
    await time.advanceBlockTo(startBlock + 2);
    expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
      2 * firstCycleRate * parseInt(rewardPerBlock)
    );
  });

  // it('Bob and Jack deposit successfully first before startBlock comes', async () => {
  //   await uniPair.connect(deployer).mint(bob.address, bobLPBeforeBalance);
  //   await uniPair.connect(bob).approve(farm.address, bobLPBeforeBalance);

  //   await uniPair.connect(deployer).mint(jack.address, jackLPBeforeBalance);
  //   await uniPair.connect(jack).approve(farm.address, jackLPBeforeBalance);

  //   await farm.connect(bob).deposit(bobLPBeforeBalance);
  //   await farm.connect(jack).deposit(jackLPBeforeBalance);

  //   await time.advanceBlockTo(startBlock + 1);
  //   expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
  //     (firstCycleRate * parseInt(rewardPerBlock)) / 2
  //   );
  //   await time.advanceBlockTo(startBlock + 2);
  //   expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
  //     (2 * firstCycleRate * parseInt(rewardPerBlock)) / 2
  //   );
  // });

  it('Bob and Jack deposit successfully first before startBlock comes', async () => {
    await uniPair.connect(deployer).mint(bob.address, bobLPBeforeBalance);
    await uniPair.connect(bob).approve(farm.address, bobLPBeforeBalance);

    await uniPair.connect(deployer).mint(jack.address, jackLPBeforeBalance);
    await uniPair.connect(jack).approve(farm.address, jackLPBeforeBalance);

    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await farm.connect(jack).deposit(jackLPBeforeBalance);

    await time.advanceBlockTo(startBlock + 1);
    expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
      (firstCycleRate * parseInt(rewardPerBlock)) / 2
    );
    await time.advanceBlockTo(startBlock + 100);
    expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
      (100 * firstCycleRate * parseInt(rewardPerBlock)) / 2
    );
  });

  it('Bob deposit successfully after that Jack deposit successfully', async () => {
    await uniPair.connect(deployer).mint(bob.address, bobLPBeforeBalance);
    await uniPair.connect(bob).approve(farm.address, bobLPBeforeBalance);

    await uniPair.connect(deployer).mint(jack.address, jackLPBeforeBalance);
    await uniPair.connect(jack).approve(farm.address, jackLPBeforeBalance);

    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 101);

    await farm.connect(jack).deposit(jackLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 200);

    let bobReward = parseInt(await farm.pendingReward(bob.address));
    let jackReward = parseInt(await farm.pendingReward(jack.address));

    expect(bobReward / jackReward).to.be.gt(2);
  });

  it('Bob deposits first time successfully, second time', async () => {
    await uniPair.connect(deployer).mint(bob.address, '2000000000000000000');
    await uniPair.connect(bob).approve(farm.address, '2000000000000000000');

    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 199);

    let bobPendingReward = parseInt(await farm.pendingReward(bob.address));
    console.log(bobPendingReward);

    await farm.connect(bob).deposit(bobLPBeforeBalance);

    let vestingContract = await ethers.getContractAt('Vesting', await farm.vesting());
    let vestingInfo = await vestingContract.getVestingInfo(bob.address, '0');

    expect(parseInt(amountToFarm)).to.be.equal(
      parseInt(vestingInfo.amount) + parseInt(await moma.balanceOf(bob.address))
    );
  });
});
