// scripts/deploy_upgradeable_box.js
import { ethers, upgrades } from "hardhat";
const hre = require("hardhat");

const underlyingAssetAddressA = "0xf4423F4152966eBb106261740da907662A3569C5";
const underlyingAssetAddressB = "0x9FD21bE27A2B059a288229361E2fA632D8D2d074";
const oracleForAssetA = "0xA39434A63A52E749F02807ae27335515BA4b07F7";
const oracleForAssetB = "0xA39434A63A52E749F02807ae27335515BA4b07F7";
const loanpct = 70000000;
const aaveInterestMode = 1;
const name = "DTX1";
const symbol = "DTX1";
const decimals = 18;

const permitUsdcAddress = "0xF042D421fA99a1F71AbEc7375Ec80C5fEA886faa"; // Used for the forwarder

async function main() {
  //Deployers address
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`Deployer's address (admin & owner): `, deployerAddress);

  // Deploy PoolFactory contract
  
  const PoolFactory = await ethers.getContractFactory("PoolFactory");
  console.log('Deploying PoolFactory contract...');
  const factory = await upgrades.deployProxy(PoolFactory, [], { initializer: 'initialize' });
  await factory.deployed();
  console.log('PoolFactory deployed to:', factory.address);

  const Forwarder = await ethers.getContractFactory("Forwarder");
  console.log("Deploying forwarder contract...");
  const forwarder = await Forwarder.deploy(permitUsdcAddress, underlyingAssetAddressB, factory.address);
  console.log("Forwarder deployed to:", forwarder.address);

  // Deploy pool using factory
  await factory.createPool("0xf4423F4152966eBb106261740da907662A3569C5", "0x9FD21bE27A2B059a288229361E2fA632D8D2d074", 7500, 2, 20000, 2000000, "Diatomix Pool #1", "DTX1", 3600);
  console.log("Pool address: ", await factory.getAllPoolInstances())
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
