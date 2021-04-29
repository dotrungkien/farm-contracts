const { ethers } = require('hardhat');
const { expect } = require('chai');
const { time, expectRevert } = require('@openzeppelin/test-helpers');

describe('Test Farming', async () => {
  let farmFactory, farmGenerator, farm, uniPair, uniFactory, moma, weth, vesting;
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
    vesting = await ethers.getContractAt('Vesting', await farm.vesting());
  });

  it.only('All setup successfully', async () => {
    expect(await farm.lpToken()).to.be.equal(uniPair.address);
    expect(await farm.rewardToken()).to.be.equal(moma.address);
    expect(parseInt(await farm.startBlock())).to.be.equal(startBlock);
    expect(parseInt(await farm.rewardPerBlock())).to.be.equal(parseInt(rewardPerBlock));
    expect(parseInt(await farm.lastRewardBlock())).to.be.equal(startBlock);
    expect(parseInt(await farm.accRewardPerShare())).to.be.equal(0);
    expect(parseInt(await farm.farmerCount())).to.be.equal(0);
    expect(parseInt(await farm.firstCycleRate())).to.be.equal(firstCycleRate);
    expect(parseInt(await farm.initRate())).to.be.equal(initRate);
    expect(parseInt(await farm.reducingRate())).to.be.equal(reducingRate);
    expect(parseInt(await farm.reducingCycle())).to.be.equal(reducingCycle);
    expect(await farm.factory()).to.be.equal(farmFactory.address);
    expect(await farm.farmGenerator()).to.be.equal(farmGenerator.address);
    expect(parseInt(await farm.percentForVesting())).to.be.equal(percentForVesting);
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
    await time.advanceBlockTo(startBlock + 200);

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
