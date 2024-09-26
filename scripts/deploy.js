const hre = require("hardhat");

async function main() {
  const ZeroxBin = await hre.ethers.getContractFactory("ZeroxBin");
  
  const devAddress = "0x9EA105F2F0954B3481D894B66E124E0A6084a52e";  // Address to receive developer tips

  const zeroxBin = await ZeroxBin.deploy(devAddress);

  await zeroxBin.deployed();

  console.log("0xBin deployed to:", zeroxBin.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });