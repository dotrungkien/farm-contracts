const { ethers } = require('hardhat');

async function main() {
  let [deployer] = await ethers.getSigners();

  let firstCycleRate = 6;
  let initRate = 3;
  let reducingRate = 95;
  let reducingCycle = 195000;

  let percentForVesting = 50;
  let vestingDuration = 195000;

  
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
