// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./interfaces/IERC20.sol";
import "./utils/SafeERC20.sol";
import "./security/ReentrancyGuard.sol";
import "./access/Ownable.sol";

/**
 * @title AlphaStaking
 * @dev Users stake ALPHA tokens to earn rewards with secure withdrawal logic and cooldowns
 * @notice This contract implements a staking mechanism with time-based rewards and withdrawal cooldowns
 */
contract AlphaStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    
    // Struct to hold staking information for each user
    struct StakingInfo {
        uint256 amount;
        uint256 lastUpdateBlock;
        uint256 rewards;
    }
    
    // Staking token (ERC20)
    IERC20 public immutable stakingToken;
    
    // Reward token (ERC20)
    IERC20 public immutable rewardToken;
    
    // Reward rate / reward per block
    uint256 public rewardRate;
    
    // Start & end blocks for staking (more secure than timestamps)
    uint256 public immutable startBlock;
    uint256 public immutable endBlock;
    
    // Mapping for user stakes (amount, timestamps, rewards)
    mapping(address => StakingInfo) public stakes;
    
    // Total staked supply
    uint256 public totalStaked;
    
    // Last update block for rewards
    uint256 public immutable lastUpdateBlock;
    
    // Array of all stakers for enumeration
    address[] public beneficiaries;
    
    // Mapping to check if address is a staker
    mapping(address => bool) public isStaker;
    
    /**
     * @dev Constructor
     * @param _stakingToken Address of the staking token contract
     * @param _rewardToken Address of the reward token contract
     * @param _rewardRate Initial reward rate per block
     * @param _startBlock Start block for staking
     * @param _endBlock End block for staking
     */
    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardRate,
        uint256 _startBlock,
        uint256 _endBlock
    ) {
        require(_stakingToken != address(0), "AlphaStaking: invalid staking token address");
        require(_rewardToken != address(0), "AlphaStaking: invalid reward token address");
        require(_startBlock > block.number, "AlphaStaking: start block must be in future");
        require(_endBlock > _startBlock, "AlphaStaking: end block must be after start block");
        
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        startBlock = _startBlock;
        endBlock = _endBlock;
        lastUpdateBlock = _startBlock;
    }
    
    // Modifiers
    
    /**
     * @dev Updates rewards for a user before any action
     * @param user Address of the user
     */
    modifier updateReward(address user) {
        if (user != address(0)) {
            stakes[user].rewards = earned(user);
            stakes[user].lastUpdateBlock = block.number;
        }
        _;
    }
    
    /**
     * @dev Ensures only stakers can access certain functions
     */
    modifier onlyStaker() {
        require(stakes[msg.sender].amount > 0, "AlphaStaking: not a staker");
        _;
    }
    
    /**
     * @dev Ensures staking period is active
     */
    modifier stakingActive() {
        require(block.number >= startBlock && block.number <= endBlock, "AlphaStaking: staking not active");
        _;
    }
    
    /**
     * @dev Stakes tokens for the caller
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant stakingActive updateReward(msg.sender) {
        require(amount > 0, "AlphaStaking: amount must be greater than 0");
        require(amount <= type(uint256).max / 1e18, "AlphaStaking: amount too large");
        
        // Check if contract has sufficient reward tokens for potential rewards
        uint256 potentialRewards = earned(msg.sender);
        require(
            rewardToken.balanceOf(address(this)) >= potentialRewards,
            "AlphaStaking: insufficient reward token balance for potential rewards"
        );
        
        // Additional security: Check for overflow in total staked
        require(totalStaked <= type(uint256).max - amount, "AlphaStaking: total staked overflow");
        
        // Update staking information BEFORE external call to prevent reentrancy
        stakes[msg.sender].amount += amount;
        totalStaked += amount;
        
        // Add to stakers list if not already there
        if (!isStaker[msg.sender]) {
            beneficiaries.push(msg.sender);
            isStaker[msg.sender] = true;
        }
        
        // Transfer tokens from user to contract AFTER state updates
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        emit Staked(msg.sender, amount);
    }
    
    /**
     * @dev Withdraws staked tokens
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant onlyStaker updateReward(msg.sender) {
        require(amount > 0, "AlphaStaking: amount must be greater than 0");
        require(stakes[msg.sender].amount >= amount, "AlphaStaking: insufficient staked amount");
        
        // Update staking information
        stakes[msg.sender].amount -= amount;
        totalStaked -= amount;
        
        // Remove from stakers list if no longer staking
        if (stakes[msg.sender].amount == 0) {
            _removeStaker(msg.sender);
        }
        
        // Transfer tokens back to user
        stakingToken.safeTransfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Claims pending rewards
     */
    function claimReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = stakes[msg.sender].rewards;
        require(reward > 0, "AlphaStaking: no rewards to claim");
        require(
            rewardToken.balanceOf(address(this)) >= reward,
            "AlphaStaking: insufficient reward token balance"
        );
        
        stakes[msg.sender].rewards = 0;
        rewardToken.safeTransfer(msg.sender, reward);
        
        emit RewardPaid(msg.sender, reward);
    }
    
    /**
     * @dev Withdraws all staked tokens and claims rewards in one call
     */
    function exit() external nonReentrant onlyStaker updateReward(msg.sender) {
        uint256 amount = stakes[msg.sender].amount;
        uint256 reward = stakes[msg.sender].rewards;
        
        require(amount > 0, "AlphaStaking: no staked tokens");
        
        // Reset staking information
        stakes[msg.sender].amount = 0;
        stakes[msg.sender].rewards = 0;
        totalStaked -= amount;
        
        // Remove from stakers list
        _removeStaker(msg.sender);
        
        // Transfer staked tokens back to user
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
        
        // Transfer rewards if any
        if (reward > 0) {
            require(
                rewardToken.balanceOf(address(this)) >= reward,
                "AlphaStaking: insufficient reward token balance"
            );
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }
    
    // View Functions
    
    /**
     * @dev Calculates earned rewards for a user
     * @param user Address of the user
     * @return Total earned rewards
     */
    function earned(address user) public view returns (uint256) {
        StakingInfo memory userStake = stakes[user];
        if (userStake.amount == 0) return userStake.rewards;
        
        uint256 blocksElapsed = block.number - userStake.lastUpdateBlock;
        // Calculate rewards based on blocks elapsed (more secure than timestamps)
        uint256 newRewards = (userStake.amount * rewardRate * blocksElapsed) / 1e18;
        
        // Additional check to prevent overflow
        if (userStake.rewards > type(uint256).max - newRewards) {
            return type(uint256).max;
        }
        
        return userStake.rewards + newRewards;
    }
    
    /**
     * @dev Gets staked balance for a user
     * @param user Address of the user
     * @return Staked balance
     */
    function balanceOf(address user) external view returns (uint256) {
        return stakes[user].amount;
    }
    
    /**
     * @dev Gets total staked amount
     * @return Total staked amount
     */
    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }
    
    /**
     * @dev Removes a staker from the stakers array
     * @param _staker Address of the staker to remove
     */
    function _removeStaker(address _staker) internal {
        if (!isStaker[_staker]) return;
        
        uint256 beneficiariesLength = beneficiaries.length;
        for (uint256 i = 0; i < beneficiariesLength; i++) {
            if (beneficiaries[i] == _staker) {
                beneficiaries[i] = beneficiaries[beneficiariesLength - 1];
                beneficiaries.pop();
                isStaker[_staker] = false;
                break;
            }
        }
    }
    
    // Admin Functions (Owner only)
    
    /**
     * @dev Sets the reward rate (owner only)
     * @param newRewardRate New reward rate per second
     */
    function setRewardRate(uint256 newRewardRate) external onlyOwner {
        require(newRewardRate <= 1e18, "AlphaStaking: reward rate too high");
        
        uint256 oldRewardRate = rewardRate;
        
        // Update all existing stakers' rewards before changing rate
        uint256 beneficiariesLength = beneficiaries.length;
        for (uint256 i = 0; i < beneficiariesLength; i++) {
            address staker = beneficiaries[i];
            if (stakes[staker].amount > 0) {
                stakes[staker].rewards = earned(staker);
                stakes[staker].lastUpdateBlock = block.number;
            }
        }
        
        rewardRate = newRewardRate;
        emit RewardRateUpdated(oldRewardRate, newRewardRate);
    }
    
    /**
     * @dev Funds the contract with reward tokens (owner only)
     * @param amount Amount of reward tokens to deposit
     */
    function fundRewards(uint256 amount) external onlyOwner {
        require(amount > 0, "AlphaStaking: amount must be greater than 0");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
    }
    
    /**
     * @dev Emergency withdraw reward tokens (owner only)
     * @param amount Amount of reward tokens to withdraw
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(
            rewardToken.balanceOf(address(this)) >= amount,
            "AlphaStaking: insufficient reward token balance"
        );
        rewardToken.safeTransfer(owner(), amount);
    }
}
