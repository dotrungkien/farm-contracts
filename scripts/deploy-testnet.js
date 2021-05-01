const { ethers, network } = require('hardhat');
require('@nomiclabs/hardhat-ethers');

async function main() {
  if (network.name !== 'bsctestnet') {
    throw new Error('Invalid network');
  }

  let [deployer] = await ethers.getSigners();

  let amount = '8000000000000000000000000'; // 8m MOMA
  let farmFactory, farmGenerator, farm;

  let rewardPerBlock = '3000000000000000000'; // 3 MOMA/block

  let startBlock = (await ethers.provider.getBlockNumber()) + 100;
  let firstCycleRate = 2;
  let initRate = 1;
  let reducingRate = 95;
  let reducingCycle = 195000; // 1 month

  let percentForVesting = 100;
  let vestingDuration = 1170000; // 6 months

  let momaTokenAddress = '';
  let pancakeRouterAddress = '0xD99D1c33F9fC3444f8101754aBC46c52416550D1';

  let momaToken, weth, lpToken, pancakeFactory, pancakeRouter;
  let tx;

  console.log('Deploy contract with the account: ', deployer.address);

  pancakeRouter = await ethers.getContractAt('IPancakeRouter', pancakeRouterAddress);

  weth = await ethers.getContractAt('WETH9', await pancakeRouter.WETH());

  pancakeFactory = await ethers.getContractAt('IPancakeFactory', await pancakeRouter.factory());

  if (momaTokenAddress === '' || momaTokenAddress === undefined) {
    console.log('\nDeploy MOMA BSC testnet');
    let TestERC20 = await ethers.getContractFactory('TestERC20');
    momaToken = await TestERC20.connect(deployer).deploy('MOchi MArket Token', 'MOMA');

    await momaToken.deployed();

    tx = await momaToken.connect(deployer).mint(deployer.address, amount);
    await tx.wait();

    tx = await pancakeFactory.createPair(weth.address, momaToken.address);
    await tx.wait();
  } else {
    momaToken = await ethers.getContractAt('IERC20', momaTokenAddress);
  }

  lpToken = await ethers.getContractAt(
    'IPancakePair',
    await pancakeFactory.getPair(momaToken.address, weth.address)
  );

  console.log('\nDeploy Farm Factory...');
  let FarmFactory = await ethers.getContractFactory('FarmFactory');
  farmFactory = await FarmFactory.connect(deployer).deploy();
  await farmFactory.deployed();

  console.log('\nDeploy Farm Generator...');
  let FarmGenerator = await ethers.getContractFactory('FarmGenerator');
  farmGenerator = await FarmGenerator.connect(deployer).deploy(
    farmFactory.address,
    pancakeFactory.address
  );
  await farmGenerator.deployed();

  tx = await farmFactory.connect(deployer).adminAllowFarmGenerator(farmGenerator.address, true);
  await tx.wait();

  tx = await momaToken.connect(deployer).approve(farmGenerator.address, amount);
  await tx.wait();

  tx = await farmGenerator
    .connect(deployer)
    .createFarm(
      momaToken.address,
      amount,
      lpToken.address,
      rewardPerBlock,
      startBlock,
      deployer.address,
      [firstCycleRate, initRate, reducingRate, reducingCycle],
      [percentForVesting, vestingDuration]
    );
  await tx.wait();

  farm = await ethers.getContractAt('Farm', await farmFactory.farmAtIndex(0));
  console.log('\n\nAll setup successfully...');
  console.log('Startblock: ', startBlock);
  console.log('LP Token: ', lpToken.address);
  console.log('MOMA: ', momaToken.address);
  console.log('WETH: ', weth.address);
  console.log('Farm Factory: ', farmFactory.address);
  console.log('Farm Generator: ', farmGenerator.address);
  console.log('Farm: ', farm.address);
  console.log('Vesting: ', await farm.vesting());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
