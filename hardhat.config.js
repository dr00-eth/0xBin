require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("dotenv").config();

module.exports = {
  solidity: "0.8.27",
  networks: {
    arbitrumOne: {
      url: `https://arbitrum-mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
      accounts: [process.env.PRIVATE_KEY]
    },
    arbitrumSepolia: {
      url: `https://arbitrum-sepolia.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
      chainId: 421614,
      accounts: [process.env.PRIVATE_KEY]
    }
  },
  etherscan: {
    apiKey: {
      arbitrumSepolia: process.env.ARBISCAN_API_KEY,
      arbitrumOne: process.env.ARBISCAN_API_KEY
    },
    customChains: [
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io"
        }
      }
    ]
  }
};