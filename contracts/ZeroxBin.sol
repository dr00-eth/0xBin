// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ZeroxBin is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    uint256 private _pasteIdCounter;

    enum PasteType { Public, Paid, Private }

    struct Paste {
        uint256 id;
        address creator;
        string title;
        bytes content;
        uint256 creationTime;
        uint256 expirationTime;
        PasteType pasteType;
        uint256 price;
        bool isDeleted;
        string publicKey;  // This is now used as the "public key" for deriving the decryption key
        mapping(address => bool) allowedAddresses;
    }

    struct PasteInfo {
        uint256 id;
        address creator;
        string title;
        uint256 creationTime;
        uint256 expirationTime;
        PasteType pasteType;
        uint256 price;
        bool isDeleted;
        string publicKey;
    }

    mapping(uint256 => Paste) public pastes;
    mapping(address => uint256[]) public userPastes;
    mapping(address => uint256[]) private accessiblePastes;
    mapping(uint256 => uint256) public nonPrivatePasteIndex;
    uint256[] public nonPrivatePasteIds;

    address public devAddress;
    uint256 public totalTips;

    event PasteCreated(uint256 indexed id, address indexed creator, string title, PasteType pasteType);
    event PasteAccessed(uint256 indexed id, address indexed accessor);
    event PasteUpdated(uint256 indexed id, address indexed updater);
    event PasteDeleted(uint256 indexed id, address indexed deleter);
    event AllowedAddressAdded(uint256 indexed id, address indexed newAddress);
    event AllowedAddressRemoved(uint256 indexed id, address indexed oldAddress);
    event TipReceived(address indexed tipper, uint256 amount);
    event DevAddressUpdated(address indexed oldDevAddress, address indexed newDevAddress);
    event PaymentReceived(uint256 indexed pasteId, address indexed payer, uint256 amount);

    constructor(address _devAddress) Ownable(msg.sender) {
        devAddress = _devAddress;
    }

    function createPublicPaste(
        string memory _title,
        string memory _content,
        uint256 _expirationTime,
        string memory _publicKey
    ) external payable nonReentrant returns (uint256) {
        require(_expirationTime == 0 || _expirationTime > block.timestamp, "Expiration time must be in the future or zero");
        uint256 newPasteId = _createPaste(_title, bytes(_content), _expirationTime, PasteType.Public, 0, _publicKey);
        nonPrivatePasteIndex[newPasteId] = nonPrivatePasteIds.length;
        nonPrivatePasteIds.push(newPasteId);
        _handleTip();
        return newPasteId;
    }

    function createPaidPaste(
        string memory _title,
        bytes memory _encryptedContent,
        uint256 _expirationTime,
        uint256 _price,
        string memory _publicKey
    ) external payable nonReentrant returns (uint256) {
        require(_expirationTime == 0 || _expirationTime > block.timestamp, "Expiration time must be in the future or zero");
        require(_price > 0, "Price must be greater than 0");
        uint256 newPasteId = _createPaste(_title, _encryptedContent, _expirationTime, PasteType.Paid, _price, _publicKey);
        nonPrivatePasteIndex[newPasteId] = nonPrivatePasteIds.length;
        nonPrivatePasteIds.push(newPasteId);
        _handleTip();
        return newPasteId;
    }

    function createPrivatePaste(
        string memory _title,
        bytes memory _encryptedContent,
        uint256 _expirationTime,
        address[] memory _allowedAddresses,
        string memory _publicKey
    ) external payable nonReentrant returns (uint256) {
        require(_expirationTime == 0 || _expirationTime > block.timestamp, "Expiration time must be in the future or zero");
        uint256 newPasteId = _createPaste(_title, _encryptedContent, _expirationTime, PasteType.Private, 0, _publicKey);
        Paste storage newPaste = pastes[newPasteId];
        for (uint i = 0; i < _allowedAddresses.length; i++) {
            newPaste.allowedAddresses[_allowedAddresses[i]] = true;
            emit AllowedAddressAdded(newPasteId, _allowedAddresses[i]);
        }
        _handleTip();
        return newPasteId;
    }

    function _createPaste(
        string memory _title,
        bytes memory _content,
        uint256 _expirationTime,
        PasteType _pasteType,
        uint256 _price,
        string memory _publicKey
    ) private returns (uint256) {
        _pasteIdCounter++;
        uint256 newPasteId = _pasteIdCounter;

        Paste storage newPaste = pastes[newPasteId];
        newPaste.id = newPasteId;
        newPaste.creator = msg.sender;
        newPaste.title = _title;
        newPaste.content = _content;
        newPaste.creationTime = block.timestamp;
        newPaste.expirationTime = _expirationTime;
        newPaste.pasteType = _pasteType;
        newPaste.price = _price;
        newPaste.publicKey = _publicKey;
        newPaste.allowedAddresses[msg.sender] = true;

        userPastes[msg.sender].push(newPasteId);
        
        accessiblePastes[msg.sender].push(newPasteId);

        emit PasteCreated(newPasteId, msg.sender, _title, _pasteType);
        return newPasteId;
    }

    function accessPaste(uint256 _pasteId) external payable nonReentrant returns (bool) {
        Paste storage paste = pastes[_pasteId];
        require(!paste.isDeleted, "Paste has been deleted");
        require(paste.expirationTime == 0 || block.timestamp <= paste.expirationTime, "Paste has expired");

        if (paste.pasteType == PasteType.Paid && !paste.allowedAddresses[msg.sender]) {
            require(msg.value == paste.price, "Payment must be exact");
            paste.allowedAddresses[msg.sender] = true;
            payable(paste.creator).transfer(msg.value);
            emit PaymentReceived(_pasteId, msg.sender, msg.value);
            emit AllowedAddressAdded(_pasteId, msg.sender);
            
            accessiblePastes[msg.sender].push(_pasteId);
        } else if (paste.pasteType == PasteType.Private) {
            require(paste.allowedAddresses[msg.sender], "You do not have access to this paste");
        }

        emit PasteAccessed(_pasteId, msg.sender);
        return true;
    }

    function getPaste(uint256 _pasteId) external view returns (
        uint256 id,
        address creator,
        string memory title,
        bytes memory content,
        uint256 creationTime,
        uint256 expirationTime,
        PasteType pasteType,
        uint256 price,
        bool hasAccess,
        string memory publicKey
    ) {
        Paste storage paste = pastes[_pasteId];
        require(!paste.isDeleted, "Paste has been deleted");
        require(paste.expirationTime == 0 || block.timestamp <= paste.expirationTime, "Paste has expired");

        bool _hasAccess = paste.pasteType == PasteType.Public || paste.allowedAddresses[msg.sender];

        return (
            paste.id,
            paste.creator,
            paste.title,
            _hasAccess ? paste.content : bytes(""),
            paste.creationTime,
            paste.expirationTime,
            paste.pasteType,
            paste.price,
            _hasAccess,
            paste.publicKey
        );
    }

    function getPasteInfo(uint256 _pasteId) external view returns (
        uint256 id,
        address creator,
        string memory title,
        uint256 creationTime,
        uint256 expirationTime,
        PasteType pasteType,
        uint256 price,
        bool isDeleted,
        string memory publicKey
    ) {
        Paste storage paste = pastes[_pasteId];
        require(!paste.isDeleted, "Paste has been deleted");
        require(paste.expirationTime == 0 || block.timestamp <= paste.expirationTime, "Paste has expired");

        return (
            paste.id,
            paste.creator,
            paste.title,
            paste.creationTime,
            paste.expirationTime,
            paste.pasteType,
            paste.price,
            paste.isDeleted,
            paste.publicKey
        );
    }

    function getPublicPaste(uint256 _pasteId) external view returns (
        uint256 id,
        address creator,
        string memory title,
        bytes memory content,
        uint256 creationTime,
        uint256 expirationTime,
        PasteType pasteType,
        uint256 price,
        string memory publicKey
    ) {
        Paste storage paste = pastes[_pasteId];
        require(!paste.isDeleted, "Paste has been deleted");
        require(paste.expirationTime == 0 || block.timestamp <= paste.expirationTime, "Paste has expired");
        require(paste.pasteType == PasteType.Public, "This function is only for public pastes");

        return (
            paste.id,
            paste.creator,
            paste.title,
            paste.content,
            paste.creationTime,
            paste.expirationTime,
            paste.pasteType,
            paste.price,
            paste.publicKey
        );
    }

    function getPrivatePaste(uint256 _pasteId) external view returns (
        uint256 id,
        address creator,
        string memory title,
        bytes memory content,
        uint256 creationTime,
        uint256 expirationTime,
        PasteType pasteType,
        uint256 price,
        string memory publicKey
    ) {
        Paste storage paste = pastes[_pasteId];
        require(!paste.isDeleted, "Paste has been deleted");
        require(paste.expirationTime == 0 || block.timestamp <= paste.expirationTime, "Paste has expired");
        require(paste.pasteType == PasteType.Private || paste.pasteType == PasteType.Paid, "This function is only for private or paid pastes");
        require(paste.allowedAddresses[msg.sender], "You do not have access to this paste");

        return (
            paste.id,
            paste.creator,
            paste.title,
            paste.content,
            paste.creationTime,
            paste.expirationTime,
            paste.pasteType,
            paste.price,
            paste.publicKey
        );
    }

    function updatePaste(uint256 _pasteId, bytes memory _newContent) external nonReentrant {
        Paste storage paste = pastes[_pasteId];
        require(msg.sender == paste.creator, "Only creator can update");
        require(!paste.isDeleted, "Paste has been deleted");

        paste.content = _newContent;
        emit PasteUpdated(_pasteId, msg.sender);
    }

    function deletePaste(uint256 _pasteId) external nonReentrant {
        Paste storage paste = pastes[_pasteId];
        require(msg.sender == paste.creator || msg.sender == owner(), "Not authorized");
        require(!paste.isDeleted, "Paste already deleted");

        paste.isDeleted = true;

        if (paste.pasteType == PasteType.Public || paste.pasteType == PasteType.Paid) {
            uint256 index = nonPrivatePasteIndex[_pasteId];
            uint256 lastPasteId = nonPrivatePasteIds[nonPrivatePasteIds.length - 1];

            nonPrivatePasteIds[index] = lastPasteId;
            nonPrivatePasteIndex[lastPasteId] = index;

            nonPrivatePasteIds.pop();
            delete nonPrivatePasteIndex[_pasteId];
        }

        emit PasteDeleted(_pasteId, msg.sender);
    }

    function addAllowedAddress(uint256 _pasteId, address _newAddress) external {
        Paste storage paste = pastes[_pasteId];
        require(msg.sender == paste.creator, "Only creator can add allowed addresses");
        require(!paste.isDeleted, "Paste has been deleted");
        require(paste.pasteType == PasteType.Private, "Can only add allowed addresses to private pastes");

        paste.allowedAddresses[_newAddress] = true;
        
        accessiblePastes[_newAddress].push(_pasteId);
        
        emit AllowedAddressAdded(_pasteId, _newAddress);
    }

    function removeAllowedAddress(uint256 _pasteId, address _addressToRemove) external {
        Paste storage paste = pastes[_pasteId];
        require(msg.sender == paste.creator, "Only creator can remove allowed addresses");
        require(!paste.isDeleted, "Paste has been deleted");
        require(paste.pasteType == PasteType.Private, "Can only remove allowed addresses from private pastes");

        paste.allowedAddresses[_addressToRemove] = false;
        
        _removeFromAccessiblePastes(_addressToRemove, _pasteId);
        
        emit AllowedAddressRemoved(_pasteId, _addressToRemove);
    }

    function _removeFromAccessiblePastes(address _user, uint256 _pasteId) private {
        uint256[] storage userAccessiblePastes = accessiblePastes[_user];
        for (uint i = 0; i < userAccessiblePastes.length; i++) {
            if (userAccessiblePastes[i] == _pasteId) {
                userAccessiblePastes[i] = userAccessiblePastes[userAccessiblePastes.length - 1];
                userAccessiblePastes.pop();
                break;
            }
        }
    }

    function getPublicPastes(uint256 _offset, uint256 _limit) external view returns (PasteInfo[] memory) {
        require(_offset < nonPrivatePasteIds.length, "Offset out of bounds");
        
        uint256 end = _offset + _limit;
        if (end > nonPrivatePasteIds.length) {
            end = nonPrivatePasteIds.length;
        }
        
        PasteInfo[] memory result = new PasteInfo[](end - _offset);
        for (uint256 i = _offset; i < end; i++) {
            uint256 pasteId = nonPrivatePasteIds[i];
            Paste storage paste = pastes[pasteId];
            if (!paste.isDeleted) {
                result[i - _offset] = PasteInfo(
                    paste.id,
                    paste.creator,
                    paste.title,
                    paste.creationTime,
                    paste.expirationTime,
                    paste.pasteType,
                    paste.price,
                    paste.isDeleted,
                    paste.publicKey
                );
            }
        }
        return result;
    }

    function getUserPastes(address _user) external view returns (uint256[] memory) {
        return userPastes[_user];
    }

    function getAccessiblePastes(address _user) external view returns (PasteInfo[] memory) {
        uint256[] memory userAccessiblePasteIds = accessiblePastes[_user];
        PasteInfo[] memory result = new PasteInfo[](userAccessiblePasteIds.length);
        uint256 validPastesCount = 0;

        for (uint256 i = 0; i < userAccessiblePasteIds.length; i++) {
            Paste storage paste = pastes[userAccessiblePasteIds[i]];
            if (!paste.isDeleted && (paste.expirationTime == 0 || block.timestamp <= paste.expirationTime)) {
                result[validPastesCount] = PasteInfo(
                    paste.id,
                    paste.creator,
                    paste.title,
                    paste.creationTime,
                    paste.expirationTime,
                    paste.pasteType,
                    paste.price,
                    paste.isDeleted,
                    paste.publicKey
                );
                validPastesCount++;
            }
        }

        // Resize the array to remove any empty slots
        assembly {
            mstore(result, validPastesCount)
        }

        return result;
    }

    function setDevAddress(address _newDevAddress) external onlyOwner {
        require(_newDevAddress != address(0), "Invalid address");
        emit DevAddressUpdated(devAddress, _newDevAddress);
        devAddress = _newDevAddress;
    }

    function getTotalTips() external view returns (uint256) {
        return totalTips;
    }

    function _handleTip() private {
        if (msg.value > 0) {
            totalTips += msg.value;
            payable(devAddress).transfer(msg.value);
            emit TipReceived(msg.sender, msg.value);
        }
    }

    // Allow the contract to receive ETH
    receive() external payable {}
}