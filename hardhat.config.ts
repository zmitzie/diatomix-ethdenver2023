import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";


dotenv.config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

let accounts;

if (process.env.PRIVATE_KEY) {
  accounts = [process.env.PRIVATE_KEY];
} else {
  accounts = {
    mnemonic:
      process.env.MNEMONIC
  };
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  mocha: {
    timeout: 100000000
  },
  networks: {
    hardhat: {
      chainId: 31337,
      allowUnlimitedContractSize: true,
      gas: 12000000,
      accounts: {mnemonic: process.env.MNEMONIC},
      forking: {
        url: process.env.GOERLI_URL || "",
        blockNumber: 8541810 //8409467
      }
    },
    goerli: {
      url: process.env.GOERLI_URL || "",
      accounts,
      timeout: 0,
    },
    fantomtest: {
      url: process.env.FANTOM_TESTNET_URL,
      accounts,
      chainId: 4002,
    },
    fantomMain: {
      url: "https://fantom-mainnet.public.blastapi.io/",
      accounts,
      chainId: 250,
    },
    polygonMain: {
      url: process.env.POLYGON_URL || "",
      accounts,
      timeout: 0,
      gasPrice: 120000000000,
    },
    polygonMumbai: {
      url: process.env.MUMBAI_URL || "",
      allowUnlimitedContractSize: true,
      accounts,
      //gasPrice: 50000000000,
    },
    ganache: {
      url: "http://127.0.0.1:8545",
      accounts,
    },
    ganacheGui: {
      url: "http://127.0.0.1:7545",
      accounts,
    },
},
contractSizer: {
  alphaSort: true,
  disambiguatePaths: false,
  runOnCompile: true,
  strict: true,
},
etherscan: {
  apiKey: {
    ftmTestnet: process.env.FTM_API_KEY,
    opera: process.env.FTM_API_KEY,
    polygonMumbai: process.env.POLYGONSCAN_API_KEY,
    polygon: process.env.POLYGONSCAN_API_KEY,
  },
},
};

export default config;
