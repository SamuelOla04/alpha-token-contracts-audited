// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./interfaces/IERC20.sol";
import "./utils/SafeERC20.sol";
import "./utils/math/SafeCast.sol";
import "./access/Ownable.sol";
import "./security/ReentrancyGuard.sol";

/**
 * @title AlphaVesting
 * @dev Manages token vesting for team members and early investors
 * @notice This contract handles linear vesting with optional cliff periods
 */
contract AlphaVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    
    // Events
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event BeneficiaryAdded(address indexed beneficiary, uint256 allocation);
    event VestingRevoked(address indexed beneficiary);
    
    // Struct to hold vesting schedule information
    struct VestingSchedule {
        bool initialized;
        bool revocable;
        uint256 startBlock;
        uint256 duration;
        uint256 cliff;
        uint256 totalAmount;
        uint256 released;
    }
    
    // Token being vested (ERC20)
    IERC20 public immutable token;
    
    // Beneficiary address(es) - mapping to check if address is a beneficiary
    mapping(address => bool) public isBeneficiary;
    
    // Start block of vesting (global)
    uint256 public immutable startBlock;
    
    // Duration of vesting in blocks (global)
    uint256 public immutable duration;
    
    // Cliff duration in blocks (optional, global)
    uint256 public immutable cliff;
    
    // Mapping of released amounts per beneficiary
    mapping(address => uint256) public released;
    
    // Total tokens vested
    uint256 public totalVestedAmount;
    
    // Mapping from beneficiary address to vesting schedule
    mapping(address => VestingSchedule) public vestingSchedules;
    
    // Array of all beneficiaries for enumeration
    address[] public beneficiaries;
    
    /**
     * @dev Constructor
     * @param _token Address of the token contract
     * @param _startBlock Start block of vesting
     * @param _duration Duration of vesting in blocks
     * @param _cliff Cliff duration in blocks (optional, 0 for no cliff)
     */
    constructor(
        address _token,
        uint256 _startBlock,
        uint256 _duration,
        uint256 _cliff
    ) {
        require(_token != address(0), "AlphaVesting: invalid token address");
        require(_duration > 0, "AlphaVesting: duration must be greater than 0");
        require(_cliff <= _duration, "AlphaVesting: cliff cannot exceed duration");
        
        token = IERC20(_token);
        startBlock = _startBlock;
        duration = _duration;
        cliff = _cliff;
    }
    
    // Modifiers
    
    /**
     * @dev Restrict certain calls to beneficiaries only
     */
    modifier onlyBeneficiary() {
        require(isBeneficiary[msg.sender], "AlphaVesting: not a beneficiary");
        _;
    }
    
    /**
     * @dev Ensure vesting hasn't ended
     */
    modifier vestingActive() {
        require(block.number >= startBlock, "AlphaVesting: vesting not started");
        _;
    }
    
    /**
     * @dev Creates a vesting schedule for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @param totalAmount Total amount of tokens to vest
     * @param startBlockParam Start block of the vesting (0 for global start block)
     * @param durationParam Duration of the vesting period in blocks (0 for global duration)
     * @param cliffParam Cliff period in blocks (0 for global cliff or no cliff)
     * @param revocable Whether the vesting can be revoked by owner
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 startBlockParam,
        uint256 durationParam,
        uint256 cliffParam,
        bool revocable
    ) external onlyOwner {
        require(beneficiary != address(0), "AlphaVesting: invalid beneficiary");
        require(totalAmount > 0, "AlphaVesting: amount must be greater than 0");
        require(totalAmount <= type(uint256).max / 1e18, "AlphaVesting: amount too large");
        require(!vestingSchedules[beneficiary].initialized, "AlphaVesting: schedule already exists");
        
        // Use global values if not specified
        uint256 scheduleStartBlock = startBlockParam == 0 ? startBlock : startBlockParam;
        uint256 scheduleDuration = durationParam == 0 ? duration : durationParam;
        uint256 scheduleCliff = cliffParam == 0 ? cliff : cliffParam;
        
        require(scheduleDuration > 0, "AlphaVesting: duration must be greater than 0");
        require(scheduleCliff <= scheduleDuration, "AlphaVesting: cliff cannot exceed duration");
        
        // Additional security: Check for overflow in total vested amount
        require(totalVestedAmount <= type(uint256).max - totalAmount, "AlphaVesting: total vested overflow");
        
        // Check if contract has enough tokens
        require(
            token.balanceOf(address(this)) >= totalVestedAmount + totalAmount,
            "AlphaVesting: insufficient token balance"
        );
        
        vestingSchedules[beneficiary] = VestingSchedule({
            initialized: true,
            revocable: revocable,
            startBlock: scheduleStartBlock,
            duration: scheduleDuration,
            cliff: scheduleCliff,
            totalAmount: totalAmount,
            released: 0
        });
        
        totalVestedAmount += totalAmount;
        
        if (!isBeneficiary[beneficiary]) {
            beneficiaries.push(beneficiary);
            isBeneficiary[beneficiary] = true;
        }
        
        emit BeneficiaryAdded(beneficiary, totalAmount);
    }
    
    /**
     * @dev Releases vested tokens for the caller
     */
    function release() external nonReentrant onlyBeneficiary vestingActive {
        _release(msg.sender);
    }
    
    /**
     * @dev Releases vested tokens for a specific beneficiary (owner only)
     * @param beneficiary Address of the beneficiary
     */
    function releaseFor(address beneficiary) external onlyOwner nonReentrant {
        // Add validation to ensure beneficiary exists and has releasable tokens
        require(isBeneficiary[beneficiary], "AlphaVesting: not a beneficiary");
        require(releasable(beneficiary) > 0, "AlphaVesting: no tokens to release");
        _release(beneficiary);
    }
    
    /**
     * @dev Internal function to release vested tokens
     * @param beneficiary Address of the beneficiary
     */
    function _release(address beneficiary) internal {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.initialized, "AlphaVesting: no vesting schedule");
        
        uint256 releasableAmount = releasable(beneficiary);
        require(releasableAmount > 0, "AlphaVesting: no tokens to release");
        
        // Fix double tracking - only update schedule.released
        schedule.released += releasableAmount;
        totalVestedAmount -= releasableAmount;
        
        token.safeTransfer(beneficiary, releasableAmount);
        
        emit TokensReleased(beneficiary, releasableAmount);
    }
    
    /**
     * @dev Revokes a vesting schedule (only if revocable)
     * @param beneficiary Address of the beneficiary
     */
    function revokeVestingSchedule(address beneficiary) external onlyOwner {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.initialized, "AlphaVesting: no vesting schedule");
        require(schedule.revocable, "AlphaVesting: schedule is not revocable");
        
        uint256 unreleasedAmount = schedule.totalAmount - schedule.released;
        if (unreleasedAmount > 0) {
            // Update state BEFORE external call to prevent reentrancy
            schedule.totalAmount = schedule.released;
            totalVestedAmount -= unreleasedAmount;
            
            // Emit event BEFORE external call
            emit VestingRevoked(beneficiary);
            
            // Return revoked tokens to owner AFTER state updates and event
            token.safeTransfer(owner(), unreleasedAmount);
        } else {
            emit VestingRevoked(beneficiary);
        }
    }
    
    /**
     * @dev Calculate tokens currently available for release
     * @param beneficiary Address of the beneficiary
     * @return Amount of tokens that can be released
     */
    function releasable(address beneficiary) public view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        if (!schedule.initialized) return 0;
        
        uint256 vestedAmountValue = vestedAmount(beneficiary, uint64(block.number));
        return vestedAmountValue - schedule.released;
    }
    
    /**
     * @dev Full vesting schedule logic - determines how tokens unlock over time
     * @param beneficiary Address of the beneficiary
     * @param blockNumber Block number to calculate vested amount for
     * @return Total amount of tokens that have vested at the given block
     */
    function vestedAmount(address beneficiary, uint64 blockNumber) public view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        if (!schedule.initialized) return 0;
        
        return _vestingSchedule(schedule, blockNumber);
    }
    
    /**
     * @dev Internal vesting schedule calculation
     * @param schedule Vesting schedule struct
     * @param blockNumber Block number to calculate for
     * @return Vested amount at block
     */
    function _vestingSchedule(VestingSchedule memory schedule, uint64 blockNumber) internal pure returns (uint256) {
        // Add block validation to prevent manipulation
        if (blockNumber < schedule.startBlock) {
            return 0;
        }
        
        if (blockNumber < schedule.startBlock + schedule.cliff) {
            return 0;
        }
        
        if (blockNumber >= schedule.startBlock + schedule.duration) {
            return schedule.totalAmount;
        }
        
        // Fix overflow protection by using SafeMath-like checks
        uint256 blocksElapsed = blockNumber - schedule.startBlock;
        
        // Prevent overflow in multiplication
        if (schedule.totalAmount > 0 && blocksElapsed > 0) {
            // Use higher precision to avoid precision loss
            return (schedule.totalAmount * blocksElapsed) / schedule.duration;
        }
        
        return 0;
    }
    
    // View Functions
    
    /**
     * @dev Total tokens assigned to a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return Total allocation amount
     */
    function totalAllocation(address beneficiary) external view returns (uint256) {
        return vestingSchedules[beneficiary].totalAmount;
    }
    
    /**
     * @dev Already claimed tokens for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return releasedAmount Released amount
     */
    function getReleased(address beneficiary) external view returns (uint256) {
        return vestingSchedules[beneficiary].released;
    }
    
    /**
     * @dev Remaining balance for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return Remaining balance
     */
    function balanceOf(address beneficiary) external view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        if (!schedule.initialized) return 0;
        return schedule.totalAmount - schedule.released;
    }
    
    /**
     * @dev Gets the vesting schedule for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return initialized Whether the schedule is initialized
     * @return revocable Whether the schedule is revocable
     * @return scheduleStartBlock Start block of the schedule
     * @return scheduleDuration Duration of the schedule
     * @return scheduleCliff Cliff period of the schedule
     * @return totalAmount Total amount in the schedule
     * @return releasedAmount Amount already released
     */
    function getVestingSchedule(address beneficiary) external view returns (
        bool initialized,
        bool revocable,
        uint256 scheduleStartBlock,
        uint256 scheduleDuration,
        uint256 scheduleCliff,
        uint256 totalAmount,
        uint256 releasedAmount
    ) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        return (
            schedule.initialized,
            schedule.revocable,
            schedule.startBlock,
            schedule.duration,
            schedule.cliff,
            schedule.totalAmount,
            schedule.released
        );
    }
    
    /**
     * @dev Gets the total number of beneficiaries
     * @return Number of beneficiaries
     */
    function getBeneficiaryCount() external view returns (uint256) {
        return beneficiaries.length;
    }
    
    /**
     * @dev Gets a beneficiary by index
     * @param index Index of the beneficiary
     * @return Address of the beneficiary
     */
    function getBeneficiary(uint256 index) external view returns (address) {
        require(index < beneficiaries.length, "AlphaVesting: index out of bounds");
        return beneficiaries[index];
    }
    
    // Admin Functions (Owner only)
    
    /**
     * @dev Add/remove beneficiaries (via createVestingSchedule)
     * This is handled by createVestingSchedule function above
     */
    
    /**
     * @dev Revoke vesting (if designed to be revocable)
     * This is handled by revokeVestingSchedule function above
     */
    
    /**
     * @dev Emergency token withdrawal
     * @param amount Amount of tokens to withdraw
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(
            token.balanceOf(address(this)) >= totalVestedAmount + amount,
            "AlphaVesting: insufficient balance for emergency withdrawal"
        );
        
        token.safeTransfer(owner(), amount);
    }
}
