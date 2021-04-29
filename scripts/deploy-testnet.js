const { ethers, network } = require('hardhat');
require('@nomiclabs/hardhat-ethers');

async function main() {
  if (network.name !== 'ropsten' && network.name !== 'rinkeby') {
    throw new Error('Invalid network');
  }

  let [deployer] = await ethers.getSigners();

  let amount = '8000000000000000000000000'; // 8m MOMA
  let farmFactory, farmGenerator, farm;

  let rewardPerBlock = '3000000000000000000'; // 3 MOMA/block

  let startBlock = (await ethers.provider.getBlockNumber()) + 20;
  let firstCycleRate = 2;
  let initRate = 1;
  let reducingRate = 95;
  let reducingCycle = 195000; // 1 month

  let percentForVesting = 100;
  let vestingDuration = 1170000; // 6 months

  let momaTokenAddress = '0x78a369C94C7f5dFbD89a26DB1b9a398aD14B5b0A';
  let uniswapV2RouterAddress = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D';

  let momaToken, weth, lpToken, uniswapV2Factory, uniswapV2Router;
  let tx;

  console.log('Deploy contract with the account: ', deployer.address);

  if (momaTokenAddress === '' || momaTokenAddress === undefined) {
    let TestERC20 = await ethers.getContractFactory('TestERC20');
    momaToken = await TestERC20.connect(deployer).deploy('MOchi MArket Token', 'MOMA');

    await momaToken.connect(deployer).mint(deployer.address, amount);
  } else {
    momaToken = await ethers.getContractAt('IERC20', momaTokenAddress);
  }

  uniswapV2Router = await ethers.getContractAt('IUniswapV2Router', uniswapV2RouterAddress);

  weth = await ethers.getContractAt('WETH9', await uniswapV2Router.WETH());

  uniswapV2Factory = await ethers.getContractAt(
    'IUniswapV2Factory',
    await uniswapV2Router.factory()
  );

  lpToken = await ethers.getContractAt(
    'IUniswapV2Pair',
    await uniswapV2Factory.getPair(momaToken.address, weth.address)
  );

  console.log('\nDeploy Farm Factory...');
  let FarmFactory = await ethers.getContractFactory('FarmFactory');
  farmFactory = await FarmFactory.connect(deployer).deploy();
  await farmFactory.deployed();

  console.log('\nDeploy Farm Generator...');
  let FarmGenerator = await ethers.getContractFactory('FarmGenerator');
  farmGenerator = await FarmGenerator.connect(deployer).deploy(
    farmFactory.address,
    uniswapV2Factory.address
  );
  await farmGenerator.deployed();

  tx = await farmFactory.connect(deployer).adminAllowFarmGenerator(farmGenerator.address, true);
  await tx.wait();

  console.log('\nCreate Farm...');
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
