// AlphaVesting Contract Tests
// This file contains test cases for the AlphaVesting contract

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AlphaVesting", function () {
  async function deployFixture() {
    const [owner, beneficiary, other] = await ethers.getSigners();

    // Deploy local MockERC20
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const token = await MockERC20.deploy("ALPHA", "ALPHA");
    await token.waitForDeployment();

    // Mint supply to owner
    await token.mint(owner.address, ethers.parseEther("1000000"));

    // Deploy vesting
    const now = (await ethers.provider.getBlock("latest")).timestamp;
    const start = now + 10; // in 10 seconds
    const duration = 60 * 60 * 24 * 30; // 30 days
    const cliff = 60; // 1 minute

    const AlphaVesting = await ethers.getContractFactory("AlphaVesting");
    const vesting = await AlphaVesting.deploy(await token.getAddress(), start, duration, cliff);
    await vesting.waitForDeployment();

    // Fund vesting contract
    const allocation = ethers.parseEther("1000");
    await token.transfer(await vesting.getAddress(), allocation);

    return { owner, beneficiary, other, token, vesting, start, duration, cliff };
  }

  it("creates schedule and prevents early release before start", async function () {
    const { beneficiary, vesting } = await deployFixture();

    const allocation = ethers.parseEther("1000");
    await vesting.createVestingSchedule(beneficiary.address, allocation, 0, 0, 0, true);

    // Immediately try to release should revert (not started)
    await expect(vesting.connect(beneficiary).release()).to.be.revertedWith("AlphaVesting: vesting not started");
  });

  it("releases after cliff passes", async function () {
    const { beneficiary, token, vesting, start, cliff } = await deployFixture();

    const allocation = ethers.parseEther("1000");
    await vesting.createVestingSchedule(beneficiary.address, allocation, 0, 0, 0, true);

    // Fast-forward past start + cliff
    await ethers.provider.send("evm_setNextBlockTimestamp", [start + cliff + 1]);
    await ethers.provider.send("evm_mine", []);

    const releasableBefore = await vesting.releasable(beneficiary.address);
    expect(releasableBefore).to.be.gt(0n);

    const balBefore = await token.balanceOf(beneficiary.address);
    await vesting.connect(beneficiary).release();
    const balAfter = await token.balanceOf(beneficiary.address);
    expect(balAfter).to.be.gt(balBefore);
  });

  it("revokes and returns unvested tokens to owner", async function () {
    const { owner, beneficiary, token, vesting, start, cliff } = await deployFixture();

    const allocation = ethers.parseEther("1000");
    await vesting.createVestingSchedule(beneficiary.address, allocation, 0, 0, 0, true);

    // Move a bit into vesting to vest some portion
    await ethers.provider.send("evm_setNextBlockTimestamp", [start + cliff + 60]);
    await ethers.provider.send("evm_mine", []);

    const ownerBalBefore = await token.balanceOf(owner.address);
    await vesting.revokeVestingSchedule(beneficiary.address);
    const ownerBalAfter = await token.balanceOf(owner.address);
    expect(ownerBalAfter).to.be.gt(ownerBalBefore);
  });
});
