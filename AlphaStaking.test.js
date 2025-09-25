// AlphaStaking Contract Tests
// This file contains test cases for the AlphaStaking contract

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AlphaStaking", function () {
  async function deployFixture() {
    const [owner, user] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const token = await MockERC20.deploy("ALPHA", "ALPHA");
    await token.waitForDeployment();

    // Mint supply
    await token.mint(owner.address, ethers.parseEther("1000000"));

    // Deploy staking
    const now = (await ethers.provider.getBlock("latest")).timestamp;
    const start = now + 10; // starts in 10s
    const end = start + 3600; // 1 hour
    const rewardRate = ethers.parseEther("0.001");

    const AlphaStaking = await ethers.getContractFactory("AlphaStaking");
    const staking = await AlphaStaking.deploy(
      await token.getAddress(),
      await token.getAddress(),
      rewardRate,
      start,
      end
    );
    await staking.waitForDeployment();

    // Fund reward tokens
    await token.transfer(await staking.getAddress(), ethers.parseEther("100000"));

    // Fund user and approve
    const amount = ethers.parseEther("100");
    await token.transfer(user.address, amount);
    await token.connect(user).approve(await staking.getAddress(), amount);

    return { owner, user, token, staking, start, end };
  }

  it("stakes after start and accrues rewards, allows claim", async function () {
    const { user, token, staking, start } = await deployFixture();

    // Move past start
    await ethers.provider.send("evm_setNextBlockTimestamp", [start + 1]);
    await ethers.provider.send("evm_mine", []);

    await staking.connect(user).stake(ethers.parseEther("100"));

    // Wait a bit to accrue
    const t = (await ethers.provider.getBlock("latest")).timestamp;
    await ethers.provider.send("evm_setNextBlockTimestamp", [t + 30]);
    await ethers.provider.send("evm_mine", []);

    const earned = await staking.earned(user.address);
    expect(earned).to.be.gt(0n);

    const balBefore = await token.balanceOf(user.address);
    await staking.connect(user).claimReward();
    const balAfter = await token.balanceOf(user.address);
    expect(balAfter).to.be.gt(balBefore);
  });

  it("withdraws staked tokens", async function () {
    const { user, token, staking, start } = await deployFixture();

    await ethers.provider.send("evm_setNextBlockTimestamp", [start + 1]);
    await ethers.provider.send("evm_mine", []);

    await staking.connect(user).stake(ethers.parseEther("100"));

    const balBefore = await token.balanceOf(user.address);
    await staking.connect(user).withdraw(ethers.parseEther("40"));
    const balAfter = await token.balanceOf(user.address);

    expect(balAfter).to.be.gt(balBefore);
  });
});
