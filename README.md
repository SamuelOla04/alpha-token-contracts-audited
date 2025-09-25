ALPHA Token Smart Contracts

This repository contains the smart contracts for the ALPHA token ecosystem, including vesting and staking mechanisms.

Overview

ALPHA is a token designed to provide value to early investors, contributors, and the community through secure vesting and staking features.

Contracts
AlphaVesting.sol

Purpose: Manages token vesting with optional cliff periods.

Key Features:

Linear vesting with customizable cliff periods

Revocable and non-revocable schedules

Emergency pause functionality

Owner-controlled schedule creation and revocation

Main Functions:

createVestingSchedule() – Creates a new vesting schedule

release() – Releases vested tokens to the caller

releaseFor() – Releases vested tokens for a specific beneficiary (owner only)

revokeVestingSchedule() – Revokes a vesting schedule (if revocable)

getReleasableAmount() – Calculates releasable tokens

getVestedAmount() – Calculates vested tokens

AlphaStaking.sol

Purpose: Allows users to stake ALPHA tokens and earn rewards with cooldown-based withdrawals.

Key Features:

Time-based reward distribution

Withdrawal cooldown periods

Emergency withdrawal with penalty

Configurable reward rates and limits

Detailed staking tracking

Main Functions:

stake() – Stakes tokens

requestWithdrawal() – Starts cooldown for withdrawal

withdraw() – Withdraws staked tokens after cooldown

claimRewards() – Claims pending rewards

emergencyWithdraw() – Emergency withdrawal with penalty

getPendingRewards() – Returns pending rewards

Security Features

Both contracts implement multiple security mechanisms:

Reentrancy protection (ReentrancyGuard)

Access control (Ownable)

Safe token transfers (SafeERC20)

Input validation and bounds checking

Emergency pause and withdrawal functions

Testing

Test files are located in the test/ directory:

AlphaVesting.test.js

AlphaStaking.test.js

Dependencies

Contracts rely on OpenZeppelin libraries:

@openzeppelin/contracts/token/ERC20/IERC20.sol

@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol

@openzeppelin/contracts/security/ReentrancyGuard.sol

@openzeppelin/contracts/access/Ownable.sol

@openzeppelin/contracts/security/Pausable.sol

Deployment
Prerequisites

Node.js and npm

Hardhat (or similar)

Access to Ethereum network (local, testnet, or mainnet)

Steps

npm install @openzeppelin/contracts
npx hardhat compile
npx hardhat test
npx hardhat run scripts/deploy.js --network <network>

Configuration
AlphaVesting

Token address

Start time, duration, cliff period, total amount

Revocability (true/false)

AlphaStaking

Token and reward token addresses

Reward rate per second

Withdrawal cooldown period

Minimum and maximum stake amounts

Security Audit

Audit Status: Complete — No vulnerabilities found

Audit methodology included static analysis, manual review, and security pattern verification.

Results:

Critical Issues: 0

High Severity: 0

Medium Severity: 0

Low Severity: 0

Informational Notes: 1 (expected OpenZeppelin behavior)

Recommendation: Contracts are production-ready and secure.

Full report available in AUDIT_REPORT.md.
