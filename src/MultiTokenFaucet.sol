// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MultiTokenFaucet is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Token interfaces
    IERC20 private mythoToken;
    IERC20 private adToken;
    IERC20 private arcasToken;
    IERC20 private sonexToken;
    IERC20 private aiweb3Token;
    IERC20 private internToken;
    IERC20 private algmToken;

    // Mappings - separate cooldowns for each token per user
    mapping(address user => mapping(address token => uint256 lastClaimTimestamp)) private _lastClaimed;
    
    // Token amounts mapping - address => amount
    mapping(address token => uint256 amount) public tokenAmounts;

    // Constants
    uint256 public constant COOLDOWN_PERIOD = 1 days;

    // Events
    event TokensClaimed(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event TokenAddressUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );
    event EmergencyWithdraw(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event TokenAmountUpdated(address indexed token, uint256 oldAmount, uint256 newAmount);

    // Custom errors
    error NotEnoughTimePassed();
    error NotEnoughBalance();
    error ZeroAddressNotAllowed();
    error InvalidTokenAddress();
    error ZeroAmountNotAllowed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _mythoToken,
        address _adToken,
        address _arcasToken,
        address _sonexToken,
        address _aiweb3Token,
        address _internToken,
        address _algmToken
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        // Validate addresses
        if (_mythoToken == address(0)) revert ZeroAddressNotAllowed();
        if (_adToken == address(0)) revert ZeroAddressNotAllowed();
        if (_arcasToken == address(0)) revert ZeroAddressNotAllowed();
        if (_sonexToken == address(0)) revert ZeroAddressNotAllowed();
        if (_aiweb3Token == address(0)) revert ZeroAddressNotAllowed();
        if (_internToken == address(0)) revert ZeroAddressNotAllowed();
        if (_algmToken == address(0)) revert ZeroAddressNotAllowed();

        // Set token addresses
        mythoToken = IERC20(_mythoToken);
        adToken = IERC20(_adToken);
        arcasToken = IERC20(_arcasToken);
        sonexToken = IERC20(_sonexToken);
        aiweb3Token = IERC20(_aiweb3Token);
        internToken = IERC20(_internToken);
        algmToken = IERC20(_algmToken);

        // Set default amounts using mapping
        tokenAmounts[_mythoToken] = 1000 ether;
        tokenAmounts[_adToken] = 300_000 ether;
        tokenAmounts[_arcasToken] = 300_000 ether;
        tokenAmounts[_sonexToken] = 300_000 ether;
        tokenAmounts[_aiweb3Token] = 300_000 ether;
        tokenAmounts[_internToken] = 300_000 ether;
        tokenAmounts[_algmToken] = 300_000 ether;
    }

    // MODIFIERS

    modifier checkIfAvailableForClaim(address _token) {
        if (!_checkIfAvailableForClaim(msg.sender, _token)) revert NotEnoughTimePassed();
        _;
    }

    modifier checkIfBalanceIsEnough(IERC20 _token, uint256 _amount) {
        if (!_checkBalance(_token, _amount)) revert NotEnoughBalance();
        _;
    }

    // EXTERNAL FUNCTIONS

    function mintMytho()
        external
        nonReentrant
        whenNotPaused
        checkIfAvailableForClaim(address(mythoToken))
        checkIfBalanceIsEnough(mythoToken, tokenAmounts[address(mythoToken)])
    {
        uint256 amount = tokenAmounts[address(mythoToken)];
        _lastClaimed[msg.sender][address(mythoToken)] = block.timestamp;
        mythoToken.safeTransfer(msg.sender, amount);
        emit TokensClaimed(msg.sender, address(mythoToken), amount);
    }

    function mintAd()
        external
        nonReentrant
        whenNotPaused
        checkIfAvailableForClaim(address(adToken))
        checkIfBalanceIsEnough(adToken, tokenAmounts[address(adToken)])
    {
        uint256 amount = tokenAmounts[address(adToken)];
        _lastClaimed[msg.sender][address(adToken)] = block.timestamp;
        adToken.safeTransfer(msg.sender, amount);
        emit TokensClaimed(msg.sender, address(adToken), amount);
    }

    function mintArcas()
        external
        nonReentrant
        whenNotPaused
        checkIfAvailableForClaim(address(arcasToken))
        checkIfBalanceIsEnough(arcasToken, tokenAmounts[address(arcasToken)])
    {
        uint256 amount = tokenAmounts[address(arcasToken)];
        _lastClaimed[msg.sender][address(arcasToken)] = block.timestamp;
        arcasToken.safeTransfer(msg.sender, amount);
        emit TokensClaimed(msg.sender, address(arcasToken), amount);
    }

    function mintSonex()
        external
        nonReentrant
        whenNotPaused
        checkIfAvailableForClaim(address(sonexToken))
        checkIfBalanceIsEnough(sonexToken, tokenAmounts[address(sonexToken)])
    {
        uint256 amount = tokenAmounts[address(sonexToken)];
        _lastClaimed[msg.sender][address(sonexToken)] = block.timestamp;
        sonexToken.safeTransfer(msg.sender, amount);
        emit TokensClaimed(msg.sender, address(sonexToken), amount);
    }

    function mintAiweb3()
        external
        nonReentrant
        whenNotPaused
        checkIfAvailableForClaim(address(aiweb3Token))
        checkIfBalanceIsEnough(aiweb3Token, tokenAmounts[address(aiweb3Token)])
    {
        uint256 amount = tokenAmounts[address(aiweb3Token)];
        _lastClaimed[msg.sender][address(aiweb3Token)] = block.timestamp;
        aiweb3Token.safeTransfer(msg.sender, amount);
        emit TokensClaimed(msg.sender, address(aiweb3Token), amount);
    }

    function mintIntern()
        external
        nonReentrant
        whenNotPaused
        checkIfAvailableForClaim(address(internToken))
        checkIfBalanceIsEnough(internToken, tokenAmounts[address(internToken)])
    {
        uint256 amount = tokenAmounts[address(internToken)];
        _lastClaimed[msg.sender][address(internToken)] = block.timestamp;
        internToken.safeTransfer(msg.sender, amount);
        emit TokensClaimed(msg.sender, address(internToken), amount);
    }

    function mintAlgm()
        external
        nonReentrant
        whenNotPaused
        checkIfAvailableForClaim(address(algmToken))
        checkIfBalanceIsEnough(algmToken, tokenAmounts[address(algmToken)])
    {
        uint256 amount = tokenAmounts[address(algmToken)];
        _lastClaimed[msg.sender][address(algmToken)] = block.timestamp;
        algmToken.safeTransfer(msg.sender, amount);
        emit TokensClaimed(msg.sender, address(algmToken), amount);
    }

    // ADMIN FUNCTIONS

    function updateTokenAddress(
        address oldAddress,
        address newAddress
    ) external onlyRole(ADMIN_ROLE) {
        if (newAddress == address(0)) revert ZeroAddressNotAllowed();
        if (oldAddress == address(0)) revert ZeroAddressNotAllowed();

        // Transfer the amount from old address to new address
        uint256 amount = tokenAmounts[oldAddress];
        if (amount > 0) {
            tokenAmounts[newAddress] = amount;
            delete tokenAmounts[oldAddress];
        }

        // Update the token reference
        if (address(mythoToken) == oldAddress) {
            mythoToken = IERC20(newAddress);
        } else if (address(adToken) == oldAddress) {
            adToken = IERC20(newAddress);
        } else if (address(arcasToken) == oldAddress) {
            arcasToken = IERC20(newAddress);
        } else if (address(sonexToken) == oldAddress) {
            sonexToken = IERC20(newAddress);
        } else if (address(aiweb3Token) == oldAddress) {
            aiweb3Token = IERC20(newAddress);
        } else if (address(internToken) == oldAddress) {
            internToken = IERC20(newAddress);
        } else if (address(algmToken) == oldAddress) {
            algmToken = IERC20(newAddress);
        } else {
            revert InvalidTokenAddress();
        }

        emit TokenAddressUpdated(oldAddress, newAddress);
    }

    function updateTokenAmount(
        address tokenAddress,
        uint256 newAmount
    ) external onlyRole(ADMIN_ROLE) {
        if (newAmount == 0) revert ZeroAmountNotAllowed();
        if (tokenAddress == address(0)) revert ZeroAddressNotAllowed();
        
        // Check if it's a valid token address
        if (tokenAddress != address(mythoToken) && 
            tokenAddress != address(adToken) && 
            tokenAddress != address(arcasToken) && 
            tokenAddress != address(sonexToken) && 
            tokenAddress != address(aiweb3Token) && 
            tokenAddress != address(internToken) && 
            tokenAddress != address(algmToken)) {
            revert InvalidTokenAddress();
        }
        
        uint256 oldAmount = tokenAmounts[tokenAddress];
        tokenAmounts[tokenAddress] = newAmount;
        
        emit TokenAmountUpdated(tokenAddress, oldAmount, newAmount);
    }

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert ZeroAddressNotAllowed();
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdraw(token, to, amount);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // VIEW FUNCTIONS

    function getLastClaimedTime(address user, address token) external view returns (uint256) {
        return _lastClaimed[user][token];
    }

    function getLastClaimedTimes(address user) external view returns (
        uint256 mytho,
        uint256 ad,
        uint256 arcas,
        uint256 sonex,
        uint256 aiweb3,
        uint256 intern,
        uint256 algm
    ) {
        return (
            _lastClaimed[user][address(mythoToken)],
            _lastClaimed[user][address(adToken)],
            _lastClaimed[user][address(arcasToken)],
            _lastClaimed[user][address(sonexToken)],
            _lastClaimed[user][address(aiweb3Token)],
            _lastClaimed[user][address(internToken)],
            _lastClaimed[user][address(algmToken)]
        );
    }

    function getTimeUntilNextClaim(address user, address token) external view returns (uint256) {
        uint256 lastClaimed = _lastClaimed[user][token];
        if (lastClaimed == 0) return 0;
        
        uint256 nextClaimTime = lastClaimed + COOLDOWN_PERIOD;
        if (block.timestamp >= nextClaimTime) return 0;
        
        return nextClaimTime - block.timestamp;
    }

    function canClaim(address user, address token) external view returns (bool) {
        return _checkIfAvailableForClaim(user, token);
    }

    function canClaimAll(address user) external view returns (
        bool mytho,
        bool ad,
        bool arcas,
        bool sonex,
        bool aiweb3,
        bool intern,
        bool algm
    ) {
        return (
            _checkIfAvailableForClaim(user, address(mythoToken)),
            _checkIfAvailableForClaim(user, address(adToken)),
            _checkIfAvailableForClaim(user, address(arcasToken)),
            _checkIfAvailableForClaim(user, address(sonexToken)),
            _checkIfAvailableForClaim(user, address(aiweb3Token)),
            _checkIfAvailableForClaim(user, address(internToken)),
            _checkIfAvailableForClaim(user, address(algmToken))
        );
    }

    function getTokenAddresses()
        external
        view
        returns (
            address mytho,
            address ad,
            address arcas,
            address sonex,
            address aiweb3,
            address intern,
            address algm
        )
    {
        return (
            address(mythoToken),
            address(adToken),
            address(arcasToken),
            address(sonexToken),
            address(aiweb3Token),
            address(internToken),
            address(algmToken)
        );
    }

    function getTokenAmounts()
        external
        view
        returns (
            uint256 mytho,
            uint256 ad,
            uint256 arcas,
            uint256 sonex,
            uint256 aiweb3,
            uint256 intern,
            uint256 algm
        )
    {
        return (
            tokenAmounts[address(mythoToken)],
            tokenAmounts[address(adToken)],
            tokenAmounts[address(arcasToken)],
            tokenAmounts[address(sonexToken)],
            tokenAmounts[address(aiweb3Token)],
            tokenAmounts[address(internToken)],
            tokenAmounts[address(algmToken)]
        );
    }

    // Get amount for specific token
    function getTokenAmount(address token) external view returns (uint256) {
        return tokenAmounts[token];
    }

    // INTERNAL FUNCTIONS

    function _checkIfAvailableForClaim(address user, address token) private view returns (bool) {
        uint256 lastClaimed = _lastClaimed[user][token];
        // If never claimed before, allow claim
        if (lastClaimed == 0) return true;
        // Check if cooldown period has passed
        return block.timestamp >= lastClaimed + COOLDOWN_PERIOD;
    }

    function _checkBalance(IERC20 _token, uint256 _amount) private view returns (bool) {
        return _token.balanceOf(address(this)) >= _amount;
    }
}
