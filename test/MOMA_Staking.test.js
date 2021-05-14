const { ethers } = require('hardhat');
const { expect } = require('chai');
const { time, expectRevert } = require('@openzeppelin/test-helpers');

describe('Test Farming', async () => {
  let farmFactory, farmGenerator, farm, pancakePair, pancakeFactory, moma, weth, vesting;
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

  let percentForVesting = 100;
  let vestingDuration = 1170000;
  beforeEach(async () => {
    [deployer, alice, bob, jack] = await ethers.getSigners();

    let TestERC20 = await ethers.getContractFactory('TestERC20');
    moma = await TestERC20.connect(deployer).deploy('MOchi MArket Token', 'MOMA');

    let WETH9 = await ethers.getContractFactory('WETH9');
    weth = await WETH9.connect(deployer).deploy();

    let MockPancakePair = await ethers.getContractFactory('MockPancakePair');
    pancakePair = await MockPancakePair.connect(deployer).deploy(
      'MOMA-WETH LP',
      'MOMA-WETH',
      moma.address,
      weth.address
    );

    let MockPancakeFactory = await ethers.getContractFactory('MockPancakeFactory');
    pancakeFactory = await MockPancakeFactory.connect(deployer).deploy();
    await pancakeFactory.connect(deployer).setPair(moma.address, weth.address, pancakePair.address);

    let FarmFactory = await ethers.getContractFactory('FarmFactory');
    farmFactory = await FarmFactory.connect(deployer).deploy();

    let FarmGenerator = await ethers.getContractFactory('FarmGenerator');
    farmGenerator = await FarmGenerator.connect(deployer).deploy(
      farmFactory.address,
      pancakeFactory.address
    );

    await farmFactory.connect(deployer).adminAllowFarmGenerator(farmGenerator.address, true);

    startBlock = parseInt(await time.latestBlock()) + 100;

    await moma.connect(deployer).mint(deployer.address, aliceMomaBeforeBalance);
    await moma.connect(deployer).approve(farmGenerator.address, aliceMomaBeforeBalance);
    await farmGenerator.connect(deployer).createFarm(
      moma.address,
      amountToFarm, // 2000 MOMA
      pancakePair.address,
      rewardPerBlock, // 2 MOMA / block
      startBlock,
      deployer.address,
      [firstCycleRate, initRate, reducingRate, reducingCycle],
      [percentForVesting, vestingDuration]
    );

    farm = await ethers.getContractAt('Farm', await farmFactory.farmAtIndex('0'));
    vesting = await ethers.getContractAt('Vesting', await farm.vesting());
  });

  it('All setup successfully', async () => {
    expect(await farm.lpToken()).to.be.equal(pancakePair.address);
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

  describe('Check multiplier', async () => {
    it('Check multiplier from startBlock to startBlock', async () => {
      expect(parseInt(await farm.getMultiplier(startBlock, startBlock))).to.be.equal(0);
    });

    it('Check multiplier from startBlock to startBlock + 1', async () => {
      expect(parseInt(await farm.getMultiplier(startBlock, startBlock + 1))).to.be.equal(
        firstCycleRate * 1e12 * 1
      );
    });

    it('Check multiplier from startBlock to startBlock + reducingCycle - 1', async () => {
      expect(
        parseInt(await farm.getMultiplier(startBlock, startBlock + reducingCycle - 1))
      ).to.be.equal(firstCycleRate * 1e12 * (reducingCycle - 1));
    });

    it('Check multiplier from startBlock to startBlock + reducingCycle', async () => {
      expect(
        parseInt(await farm.getMultiplier(startBlock, startBlock + reducingCycle))
      ).to.be.equal(firstCycleRate * 1e12 * reducingCycle);
    });

    it('Check multiplier from startBlock to startBlock + reducingCycle + 100', async () => {
      expect(
        parseInt(await farm.getMultiplier(startBlock, startBlock + reducingCycle + 100))
      ).to.be.equal(firstCycleRate * 1e12 * reducingCycle + 100 * initRate * 1e12);
    });

    it('Check multiplier from startBlock to startBlock + reducingCycle * 2', async () => {
      expect(
        parseInt(await farm.getMultiplier(startBlock, startBlock + reducingCycle * 2))
      ).to.be.equal(firstCycleRate * 1e12 * reducingCycle + initRate * 1e12 * reducingCycle);
    });

    it('Check multiplier from startBlock to startBlock + reducingCycle * 2 + 1000', async () => {
      expect(
        parseInt(await farm.getMultiplier(startBlock, startBlock + reducingCycle * 2 + 1000))
      ).to.be.equal(
        firstCycleRate * 1e12 * reducingCycle +
        initRate * 1e12 * reducingCycle +
        ((1e12 * initRate * reducingRate) / 100) * 1000
      );
    });

    it('Check multiplier from startBlock + reducingCycle + 1 to startBlock + reducingCycle * 2 + 1000', async () => {
      expect(
        parseInt(
          await farm.getMultiplier(
            startBlock + reducingCycle + 1,
            startBlock + reducingCycle * 2 + 1000
          )
        )
      ).to.be.equal(
        parseInt(await farm.getMultiplier(startBlock, startBlock + reducingCycle * 2 + 1000)) -
        parseInt(await farm.getMultiplier(startBlock, startBlock + reducingCycle + 1))
      );
    });
  });

  it('Bob deposit successfully first and only bob in pool', async () => {
    await pancakePair.connect(deployer).mint(bob.address, bobLPBeforeBalance);
    await pancakePair.connect(bob).approve(farm.address, bobLPBeforeBalance);
    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
      10 * firstCycleRate * parseInt(rewardPerBlock)
    );
  });

  it('Bob and Jack deposit successfully before startBlock comes', async () => {
    await pancakePair.connect(deployer).mint(bob.address, bobLPBeforeBalance);
    await pancakePair.connect(bob).approve(farm.address, bobLPBeforeBalance);

    await pancakePair.connect(deployer).mint(jack.address, jackLPBeforeBalance);
    await pancakePair.connect(jack).approve(farm.address, jackLPBeforeBalance);

    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await farm.connect(jack).deposit(jackLPBeforeBalance);

    await time.advanceBlockTo(startBlock + 10);
    expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
      parseInt(await farm.pendingReward(jack.address))
    );
  });

  it('Bob and Jack deposit successfully first before startBlock comes', async () => {
    await pancakePair.connect(deployer).mint(bob.address, bobLPBeforeBalance);
    await pancakePair.connect(bob).approve(farm.address, bobLPBeforeBalance);

    await pancakePair.connect(deployer).mint(jack.address, jackLPBeforeBalance);
    await pancakePair.connect(jack).approve(farm.address, jackLPBeforeBalance);

    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await farm.connect(jack).deposit(jackLPBeforeBalance);

    await time.advanceBlockTo(startBlock + 1);
    expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
      (firstCycleRate * parseInt(rewardPerBlock)) / 2
    );
    await time.advanceBlockTo(startBlock + 10);
    expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
      (10 * firstCycleRate * parseInt(rewardPerBlock)) / 2
    );
  });

  it('Bob deposit successfully before startBlock comes, Jack deposit successfully at startBlock + 10', async () => {
    await pancakePair.connect(deployer).mint(bob.address, bobLPBeforeBalance);
    await pancakePair.connect(bob).approve(farm.address, bobLPBeforeBalance);

    await pancakePair.connect(deployer).mint(jack.address, jackLPBeforeBalance);
    await pancakePair.connect(jack).approve(farm.address, jackLPBeforeBalance);

    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(
      rewardPerBlock * firstCycleRate * 10
    );

    await farm.connect(jack).deposit(jackLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 20);

    let bobReward = parseInt(await farm.pendingReward(bob.address));
    let jackReward = parseInt(await farm.pendingReward(jack.address));

    expect(bobReward / jackReward).to.be.gt(
      (parseInt(bobLPBeforeBalance) * 20) / (parseInt(jackLPBeforeBalance) * 10)
    );
  });

  it('Bob deposits first time successfully, second time', async () => {
    await pancakePair
      .connect(deployer)
      .mint(bob.address, (2 * parseInt(bobLPBeforeBalance)).toString());
    await pancakePair.connect(bob).approve(farm.address, (2 * parseInt(bobLPBeforeBalance)).toString());

    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    let bobPendingReward = parseInt(await farm.pendingReward(bob.address));
    expect(bobPendingReward).to.be.equal(10 * firstCycleRate * parseInt(rewardPerBlock));

    await farm.connect(bob).deposit(bobLPBeforeBalance);

    expect(parseInt(await farm.pendingReward(bob.address))).to.be.equal(0);
    expect(parseInt(await moma.balanceOf(vesting.address))).to.be.equal(
      ((bobPendingReward + 1 * firstCycleRate * parseInt(rewardPerBlock)) * percentForVesting) / 100
    );
  });

  it('Bob deposits successfully, when he deposit seconde time, moma in Farm less than his pendingReward', async () => {
    await pancakePair
      .connect(deployer)
      .mint(bob.address, (2 * parseInt(bobLPBeforeBalance)).toString());
    await pancakePair.connect(bob).approve(farm.address, (2 * parseInt(bobLPBeforeBalance)).toString());

    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    let bobPendingReward = parseInt(await farm.pendingReward(bob.address));

    await farm
      .connect(deployer)
      .rescueFunds(moma.address, deployer.address, '1890000000000000000000');

    let farmRewardBalance = parseInt(await moma.balanceOf(farm.address));

    expect(farmRewardBalance).to.be.lt(bobPendingReward);

    await farm.connect(bob).deposit(0);
    expect(parseInt(await moma.balanceOf(vesting.address))).to.be.equal(
      (farmRewardBalance * percentForVesting) / 100
    );

    expect(parseInt(await vesting.getTotalAmountLockedByUser(bob.address))).to.be.equal(
      farmRewardBalance
    );
  });

  it('Bob deposits successfully, when he withdraw, moma in Farm less than his pendingReward', async () => {
    await pancakePair
      .connect(deployer)
      .mint(bob.address, (2 * parseInt(bobLPBeforeBalance)).toString());
    await pancakePair.connect(bob).approve(farm.address, (2 * parseInt(bobLPBeforeBalance)).toString());

    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    let bobPendingReward = parseInt(await farm.pendingReward(bob.address));

    await farm
      .connect(deployer)
      .rescueFunds(moma.address, deployer.address, '1890000000000000000000');

    let farmRewardBalance = parseInt(await moma.balanceOf(farm.address));

    expect(farmRewardBalance).to.be.lt(bobPendingReward);

    await farm.connect(bob).deposit(0);
    expect(parseInt(await moma.balanceOf(vesting.address))).to.be.equal(
      (farmRewardBalance * percentForVesting) / 100
    );

    expect(parseInt(await vesting.getTotalAmountLockedByUser(bob.address))).to.be.equal(
      farmRewardBalance
    );
  });

  it('Only farm owner can call updateReducingRate updatePercentForVesting forceEnd transferOwnership', async () => {
    await expectRevert(farm.connect(bob).updateReducingRate(90), 'Farm: FORBIDDEN');
    await expectRevert(farm.connect(bob).updatePercentForVesting(90), 'Farm: FORBIDDEN');
    await expectRevert(farm.connect(bob).forceEnd(), 'Farm: FORBIDDEN');
    await expectRevert(farm.connect(bob).transferOwnership(bob.address), 'Farm: FORBIDDEN');
  });

  it('Update reducing rate successfully', async () => {
    let oldMultiplier = parseInt(
      await farm.getMultiplier(startBlock, startBlock + reducingCycle * 2 + 1000)
    );

    let newReducingRate = 90;
    await farm.connect(deployer).updateReducingRate(90);
    let newMultiplier = parseInt(
      await farm.getMultiplier(startBlock, startBlock + reducingCycle * 2 + 1000)
    );

    expect(newMultiplier).to.be.equal(
      firstCycleRate * 1e12 * reducingCycle +
      initRate * 1e12 * reducingCycle +
      ((1e12 * initRate * newReducingRate) / 100) * 1000
    );

    expect(newMultiplier).to.be.lt(oldMultiplier);
  });

  it('Force end successfully', async () => {
    await pancakePair.connect(deployer).mint(bob.address, bobLPBeforeBalance);
    await pancakePair.connect(bob).approve(farm.address, bobLPBeforeBalance);

    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    await farm.connect(deployer).forceEnd();
    let oldBobPendingReward = parseInt(await farm.pendingReward(bob.address));

    await time.advanceBlockTo(startBlock + 20);

    let newBobPendingReward = parseInt(await farm.pendingReward(bob.address));
    expect(newBobPendingReward).to.be.equal(oldBobPendingReward);
  });
});
