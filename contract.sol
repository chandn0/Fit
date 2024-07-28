// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WhoopieChallengeContract is ReentrancyGuard, Ownable {
    struct Challenge {
        address challenger;
        address challenged;
        address tokenAddress;
        uint256 challengerAmount;
        uint256 endTime;
        string challengeCode;
        uint256 challengeTarget;
        bool isCompleted;
        bool targetReached;
        bool isAccepted;
        bool isTwoSided;
    }

    mapping(uint256 => Challenge) public challenges;
    uint256 public challengeCounter;


    // Mapping to keep track of fees for each token
    mapping(address => uint256) public accumulatedFees;


    mapping(address => uint256[]) public userCreatedChallenges;
    mapping(address => uint256[]) public userReceivedChallenges;

    event ChallengeCreated(uint256 challengeId, address challenger, address challenged, address tokenAddress, uint256 endTime, string challengeCode, uint256 challengeTarget, bool isTwoSided);
    event ChallengeAccepted(uint256 challengeId, uint256 amount);
    event ChallengeCompleted(uint256 challengeId, bool targetReached);
    event RewardClaimed(uint256 challengeId, address winner, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {}


    function createChallenge(
        address _challenged,
        address _tokenAddress,
        uint256 _amount,
        uint256 _endTime,
        string memory _challengeCode,
        uint256 _challengeTarget,
        bool _isTwoSided
    ) external {
        require(_endTime > block.timestamp, "End time must be in the future");
        require(_amount > 0, "Amount must be greater than zero");

        IERC20 token = IERC20(_tokenAddress);
        require(token.allowance(msg.sender, address(this)) >= _amount, "Insufficient token allowance");

        uint256 challengeId = challengeCounter++;
        Challenge storage newChallenge = challenges[challengeId];

        newChallenge.challenger = msg.sender;
        newChallenge.challenged = _challenged;
        newChallenge.tokenAddress = _tokenAddress;
        newChallenge.challengerAmount = _amount;
        newChallenge.endTime = _endTime;
        newChallenge.challengeCode = _challengeCode;
        newChallenge.challengeTarget = _challengeTarget;
        newChallenge.isTwoSided = _isTwoSided;
        userCreatedChallenges[msg.sender].push(challengeId);
        if (msg.sender != _challenged) {
            userReceivedChallenges[_challenged].push(challengeId);
        }

        emit ChallengeCreated(challengeId, msg.sender, _challenged, _tokenAddress, _endTime, _challengeCode, _challengeTarget, _isTwoSided);
    }

    function acceptChallenge(uint256 _challengeId) external {
        Challenge storage challenge = challenges[_challengeId];
        require(msg.sender == challenge.challenged, "Only the challenged user can accept");
        require(!challenge.isAccepted, "Challenge already accepted");
        require(block.timestamp < challenge.endTime, "Challenge has expired");

        IERC20 token = IERC20(challenge.tokenAddress);

        if (challenge.isTwoSided) {
            require(token.allowance( challenge.challenged, address(this)) >= challenge.challengerAmount, "Insufficient token allowance for two-sided challenge");
            require(token.allowance(msg.sender, address(this)) >= challenge.challengerAmount, "Insufficient token allowance for two-sided challenge");
            require(token.transferFrom(challenge.challenged, address(this), challenge.challengerAmount), "Token transfer failed from challenger");
            require(token.transferFrom(msg.sender, address(this), challenge.challengerAmount), "Token transfer failed from challenged");
        } else {
            require(token.allowance( challenge.challenged, address(this)) >= challenge.challengerAmount, "Insufficient token allowance for two-sided challenge");
            require(token.transferFrom(challenge.challenged, address(this), challenge.challengerAmount), "Token transfer failed");
        }

        challenge.isAccepted = true;

        emit ChallengeAccepted(_challengeId, challenge.challengerAmount);
    }

     // Function to allow the owner to collect fees for a specific token
    function collectFees(address _tokenAddress) external onlyOwner nonReentrant {
        uint256 feeAmount = accumulatedFees[_tokenAddress];
        require(feeAmount > 0, "No fees to collect for this token");

        IERC20 token = IERC20(_tokenAddress);
        require(token.transfer(owner(), feeAmount), "Fee transfer failed");

        // Reset accumulated fees for this token
        accumulatedFees[_tokenAddress] = 0;

        emit FeesCollected(_tokenAddress, feeAmount);
    }

    function updateTargetStatus(uint256 _challengeId, bool _targetReached) external onlyOwner {
        Challenge storage challenge = challenges[_challengeId];
        require(block.timestamp >= challenge.endTime, "Challenge not yet ended");
        require(!challenge.isCompleted, "Challenge already completed");
        require(challenge.isAccepted, "Challenge was not accepted");

        challenge.isCompleted = true;
        challenge.targetReached = _targetReached;

        emit ChallengeCompleted(_challengeId, _targetReached);
    }

    function claim(uint256 _challengeId) external nonReentrant {
        Challenge storage challenge = challenges[_challengeId];
        require(challenge.isCompleted, "Challenge not completed yet");
        require(challenge.isAccepted, "Challenge was not accepted");

        address winner;
        uint256 rewardAmount;

        if (challenge.targetReached) {
            winner = challenge.challenged;
            rewardAmount = challenge.isTwoSided ? 2*challenge.challengerAmount : challenge.challengerAmount;
        } else {
            winner = challenge.challenger;
            rewardAmount = challenge.isTwoSided ? 2*challenge.challengerAmount : challenge.challengerAmount;
        }

        require(msg.sender == winner, "Only the winner can claim the reward");

        uint256 fee = rewardAmount * 2 / 100; // 2% fee
        uint256 winnerReward = rewardAmount - fee;

        IERC20(challenge.tokenAddress).transfer(winner, winnerReward);
        // The fee remains in the contract

                // Update accumulated fees
        accumulatedFees[challenge.tokenAddress] += fee;

        emit RewardClaimed(_challengeId, winner, winnerReward);
    }


    function isTwoSidedChallenge(uint256 _challengeId) external view returns (bool) {
        return challenges[_challengeId].isTwoSided;
    }


    // 1. View all challenges created by an address
    function getChallengesCreatedBy(address _user) external view returns (uint256[] memory) {
        return userCreatedChallenges[_user];
    }

    // 2. View all challenges received by an address
    function getChallengesReceivedBy(address _user) external view returns (uint256[] memory) {
        return userReceivedChallenges[_user];
    }

    // 3. View all accepted challenges by an address
    function getAcceptedChallengesBy(address _user) external view returns (uint256[] memory) {
        uint256[] memory receivedChallenges = userReceivedChallenges[_user];
        uint256[] memory acceptedChallenges = new uint256[](receivedChallenges.length);
        uint256 count = 0;

        for (uint256 i = 0; i < receivedChallenges.length; i++) {
            if (challenges[receivedChallenges[i]].isAccepted) {
                acceptedChallenges[count] = receivedChallenges[i];
                count++;
            }
        }

        // Resize the array to remove empty slots
        assembly {
            mstore(acceptedChallenges, count)
        }

        return acceptedChallenges;
    }

    // 4. View all active challenges for an address (either as challenger or challenged)
    function getActiveChallengesForUser(address _user) external view returns (uint256[] memory) {
        uint256[] memory createdChallenges = userCreatedChallenges[_user];
        uint256[] memory receivedChallenges = userReceivedChallenges[_user];
        uint256[] memory activeChallenges = new uint256[](createdChallenges.length + receivedChallenges.length);
        uint256 count = 0;

        for (uint256 i = 0; i < createdChallenges.length; i++) {
            if (!challenges[createdChallenges[i]].isCompleted && challenges[createdChallenges[i]].endTime > block.timestamp) {
                activeChallenges[count] = createdChallenges[i];
                count++;
            }
        }

        for (uint256 i = 0; i < receivedChallenges.length; i++) {
            if (!challenges[receivedChallenges[i]].isCompleted && challenges[receivedChallenges[i]].endTime > block.timestamp) {
                activeChallenges[count] = receivedChallenges[i];
                count++;
            }
        }

        // Resize the array to remove empty slots
        assembly {
            mstore(activeChallenges, count)
        }

        return activeChallenges;
    }

    // 5. View challenge details for multiple challenge IDs
    function getMultipleChallengeDetails(uint256[] calldata _challengeIds) external view returns (Challenge[] memory) {
        Challenge[] memory multipleChallenges = new Challenge[](_challengeIds.length);

        for (uint256 i = 0; i < _challengeIds.length; i++) {
            multipleChallenges[i] = challenges[_challengeIds[i]];
        }

        return multipleChallenges;
    }



    // Function to view accumulated fees for a specific token
    function getAccumulatedFees(address _tokenAddress) external view returns (uint256) {
        return accumulatedFees[_tokenAddress];
    }

  // Event to emit when fees are collected
    event FeesCollected(address tokenAddress, uint256 amount);
}