const { ethers } = require('hardhat');
const { expect } = require('chai');
const { time } = require('@openzeppelin/test-helpers');

describe('Test Farming', async () => {
  let farmFactory, farmGenerator, farm, uniPair, uniFactory, moma, weth;
  let deployer, alice, bob, jack;
  let startBlock, bonusEndBlock, endBlock;
  let aliceMomaBeforeBalance = '1000000000000000000000000';
  let bobLPBeforeBalance = '1000000000000000000';
  let jackLPBeforeBalance = '1000000000000000000';

  before(async () => {
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
    bonusEndBlock = startBlock + 100;

    await moma.connect(deployer).mint(alice.address, aliceMomaBeforeBalance);
    await moma.connect(alice).approve(farmGenerator.address, aliceMomaBeforeBalance);
    await farmGenerator.connect(alice).createFarm(
      moma.address,
      '2000000000000000000000', // 2000 MOMA
      uniPair.address,
      '2000000000000000000', // 2 MOMA / block
      startBlock,
      bonusEndBlock,
      '2', // 2x for multipiler,
      ['50', '24', '7'],
      {
        value: '0x2C68AF0BB140000',
      }
    );

    farm = await ethers.getContractAt('Farm', await farmFactory.farmAtIndex('0'));
    let farmInfo = await farm.farmInfo();
    endBlock = parseInt(farmInfo.endBlock);
  });

  it('All setup successfully', async () => {
    console.log('Start block: ', startBlock);
    console.log('Bonus end block: ', bonusEndBlock);
    console.log('End block: ', endBlock);
    let forFarm =
      ((bonusEndBlock - startBlock) * 2 + (endBlock - bonusEndBlock)) *
      parseInt('2000000000000000000');
    let fee = forFarm / 100;

    expect(parseInt(await moma.balanceOf(deployer.address))).to.be.equal(fee);
    expect(parseInt(await moma.balanceOf(farm.address))).to.be.equal(forFarm);
  });

  it('Bob deposit successfully', async () => {
    await uniPair.connect(deployer).mint(bob.address, bobLPBeforeBalance);
    await uniPair.connect(bob).approve(farm.address, bobLPBeforeBalance);
    await uniPair.connect(deployer).mint(jack.address, jackLPBeforeBalance);
    await uniPair.connect(jack).approve(farm.address, jackLPBeforeBalance);

    console.log('Bob and Jack deposit 1000000000000000000');
    await farm.connect(bob).deposit(bobLPBeforeBalance);
    await farm.connect(jack).deposit(jackLPBeforeBalance);

    console.log('\nCurrent block: ', parseInt(await time.latestBlock()));
    console.log('Bob pending reward: ', parseInt(await farm.pendingReward(bob.address)));
    console.log('Jack pending reward: ', parseInt(await farm.pendingReward(jack.address)));

    await time.advanceBlockTo(startBlock + 1);
    console.log('\nCurrent block: ', parseInt(await time.latestBlock()));
    console.log('Bob pending reward: ', parseInt(await farm.pendingReward(bob.address)));
    console.log('Jack pending reward: ', parseInt(await farm.pendingReward(jack.address)));

    await time.advanceBlockTo(startBlock + 100);
    console.log('\nCurrent block: ', parseInt(await time.latestBlock()));
    console.log('Bob pending reward: ', parseInt(await farm.pendingReward(bob.address)));
    console.log('Jack pending reward: ', parseInt(await farm.pendingReward(jack.address)));

    console.log('\nBob withdraw 500000000000000000');
    await farm.connect(bob).withdraw('500000000000000000');
    console.log('Current block: ', parseInt(await time.latestBlock()));
    console.log('Bob reward balance: ', parseInt(await moma.balanceOf(bob.address)));
    console.log(
      'Vesting Contract reward balance: ',
      parseInt(await moma.balanceOf(await farm.vesting()))
    );
    console.log('Bob pending reward: ', parseInt(await farm.pendingReward(bob.address)));
    console.log('Jack pending reward: ', parseInt(await farm.pendingReward(jack.address)));

    await time.advanceBlockTo(startBlock + 200);
    console.log('\nCurrent block: ', parseInt(await time.latestBlock()));
    console.log('Bob reward balance: ', parseInt(await moma.balanceOf(bob.address)));
    console.log('Bob pending reward: ', parseInt(await farm.pendingReward(bob.address)));
    console.log('Jack pending reward: ', parseInt(await farm.pendingReward(jack.address)));
  });
});
