// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMandateVerifier} from "./interfaces/IMandateVerifier.sol";
import {IMandatedContract} from "./interfaces/IMandatedContract.sol";

/// @title CouponServicer
/// @notice Services a bond's coupons. One coupon record per period, written by three mandated parties:
///           - Registrar:    who is entitled (holders and units at the record date)
///           - Calc Agent:   the fixing (rate, amount per unit, hash of the CDM Reset)
///           - Paying Agent: the payment (pays every entitled holder, hash of the CDM Transfer)
///         CDM computes; the contract records and enforces.
/// @dev Two layers of control, split by purpose:
///         - Governance (who configures the contract): OpenZeppelin AccessControl. The admin can
///           only change which mandate verifier is trusted. The admin cannot service the bond.
///         - Servicing (who services the bond): mandates, checked through IMandateVerifier on
///           every call. The contract never grants agents anything itself.
///      Each step is write-once per period. Coupons are keyed by period, so period 2, 3, ...
///      reuse the same functions and the same mandates.
contract CouponServicer is AccessControl, IMandatedContract {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------
    // Servicing roles (mandate types, checked as attestations, not granted as AccessControl roles)
    // ---------------------------------------------------------------

    bytes32 public constant REGISTRAR = keccak256("REGISTRAR");
    bytes32 public constant CALC_AGENT = keccak256("CALC_AGENT");
    bytes32 public constant PAYING_AGENT = keccak256("PAYING_AGENT");

    // ---------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------

    /// @inheritdoc IMandatedContract
    address public immutable issuer;

    /// @notice Cash token holders are paid in (6 decimals, e.g. a USDC-like stablecoin).
    IERC20 public immutable cash;

    /// @notice Who answers "is this party mandated?". Changeable by governance only.
    IMandateVerifier public verifier;

    struct Coupon {
        // Registrar: entitlement
        bool snapshotRecorded;
        uint64 recordDate;
        address[] holders;
        uint256 totalUnits; // sum of units (denominations) held at the record date
        // Calc Agent: fixing
        uint256 rate; // in units of 0.0001% (5.20% = 52000). Recorded for audit; payment uses amountPerUnit
        uint256 amountPerUnit; // cash per unit, 6 decimals
        bytes32 resetHash; // hash of the Calc Agent's CDM Reset
        // Paying Agent: payment
        bytes32 transferHash; // hash of the Paying Agent's CDM Transfer
        bool paid;
    }

    mapping(uint256 period => Coupon) internal coupons;

    /// @notice Units each holder held at the period's record date.
    mapping(uint256 period => mapping(address holder => uint256 units)) public holdingAt;

    // ---------------------------------------------------------------
    // Errors and events
    // ---------------------------------------------------------------

    error NotMandated(address caller, bytes32 role);
    error SnapshotAlreadyRecorded(uint256 period);
    error CouponAlreadySet(uint256 period);
    error AlreadyPaid(uint256 period);
    error SnapshotMissing(uint256 period);
    error CouponMissing(uint256 period);
    error LengthMismatch();
    error EmptySnapshot();
    error ZeroUnits(address holder);
    error DuplicateHolder(address holder);
    error ZeroAmount();
    error InsufficientCash(uint256 available, uint256 required);

    event VerifierSet(IMandateVerifier indexed verifier);
    event SnapshotRecorded(uint256 indexed period, address indexed registrar, uint64 recordDate, uint256 totalUnits);
    event CouponSet(
        uint256 indexed period, address indexed calcAgent, uint256 rate, uint256 amountPerUnit, bytes32 resetHash
    );
    event CouponPaid(
        uint256 indexed period, address indexed payingAgent, uint256 total, bytes32 transferHash, bytes32 resetHash
    );

    // ---------------------------------------------------------------
    // Setup
    // ---------------------------------------------------------------

    /// @param admin     governance: may change the trusted verifier (in the demo, the issuer)
    /// @param issuer_   the party entitled to appoint agents (attests their mandates)
    /// @param verifier_ the mandate verifier to trust
    /// @param cash_     the cash token coupons are paid in
    constructor(address admin, address issuer_, IMandateVerifier verifier_, IERC20 cash_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        issuer = issuer_;
        verifier = verifier_;
        cash = cash_;
        emit VerifierSet(verifier_);
    }

    /// @notice Governance: point the contract at a different mandate verifier (a new proof source).
    ///         Function bodies and mandates for the servicing roles do not change.
    function setVerifier(IMandateVerifier verifier_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        verifier = verifier_;
        emit VerifierSet(verifier_);
    }

    /// @inheritdoc IMandatedContract
    function isMandateRole(bytes32 role) external pure returns (bool) {
        return role == REGISTRAR || role == CALC_AGENT || role == PAYING_AGENT;
    }

    modifier onlyMandated(bytes32 role) {
        if (!verifier.isMandated(msg.sender, address(this), role)) revert NotMandated(msg.sender, role);
        _;
    }

    // ---------------------------------------------------------------
    // Servicing: one write per mandated party, each write-once per period
    // ---------------------------------------------------------------

    /// @notice Registrar records who held the bond at the record date, and how many units each.
    /// @dev In production this comes from the token register (e.g. ERC-3643) at the record date.
    function recordSnapshot(uint256 period, uint64 recordDate, address[] calldata holders, uint256[] calldata units)
        external
        onlyMandated(REGISTRAR)
    {
        Coupon storage c = coupons[period];
        if (c.snapshotRecorded) revert SnapshotAlreadyRecorded(period);
        if (holders.length != units.length) revert LengthMismatch();
        if (holders.length == 0) revert EmptySnapshot();

        uint256 total;
        for (uint256 i; i < holders.length; ++i) {
            if (units[i] == 0) revert ZeroUnits(holders[i]);
            if (holdingAt[period][holders[i]] != 0) revert DuplicateHolder(holders[i]);
            holdingAt[period][holders[i]] = units[i];
            total += units[i];
        }

        c.snapshotRecorded = true;
        c.recordDate = recordDate;
        c.holders = holders;
        c.totalUnits = total;
        emit SnapshotRecorded(period, msg.sender, recordDate, total);
    }

    /// @notice Calc Agent records the coupon CDM computed off-chain, with the hash of its CDM Reset.
    function setCoupon(uint256 period, uint256 rate, uint256 amountPerUnit, bytes32 resetHash)
        external
        onlyMandated(CALC_AGENT)
    {
        Coupon storage c = coupons[period];
        if (c.amountPerUnit != 0) revert CouponAlreadySet(period);
        if (amountPerUnit == 0) revert ZeroAmount();

        c.rate = rate;
        c.amountPerUnit = amountPerUnit;
        c.resetHash = resetHash;
        emit CouponSet(period, msg.sender, rate, amountPerUnit, resetHash);
    }

    /// @notice Paying Agent pays every entitled holder `units * amountPerUnit` from the contract's cash,
    ///         and links the payment (CDM Transfer hash) to the fixing it relied on (CDM Reset hash).
    /// @dev Amounts come from storage, never from the caller. Checks-effects-interactions.
    function pay(uint256 period, bytes32 transferHash) external onlyMandated(PAYING_AGENT) {
        Coupon storage c = coupons[period];
        if (!c.snapshotRecorded) revert SnapshotMissing(period);
        if (c.amountPerUnit == 0) revert CouponMissing(period);
        if (c.paid) revert AlreadyPaid(period);

        uint256 total = c.totalUnits * c.amountPerUnit;
        uint256 available = cash.balanceOf(address(this));
        if (available < total) revert InsufficientCash(available, total);

        c.paid = true;
        c.transferHash = transferHash;

        address[] storage holders = c.holders;
        for (uint256 i; i < holders.length; ++i) {
            cash.safeTransfer(holders[i], holdingAt[period][holders[i]] * c.amountPerUnit);
        }
        emit CouponPaid(period, msg.sender, total, transferHash, c.resetHash);
    }

    // ---------------------------------------------------------------
    // Reads: one value per call (Tom's CDM plugin reads one value at a time)
    // ---------------------------------------------------------------

    function recordDateOf(uint256 period) external view returns (uint64) {
        return coupons[period].recordDate;
    }

    function holdersOf(uint256 period) external view returns (address[] memory) {
        return coupons[period].holders;
    }

    function totalUnitsOf(uint256 period) external view returns (uint256) {
        return coupons[period].totalUnits;
    }

    function rateOf(uint256 period) external view returns (uint256) {
        return coupons[period].rate;
    }

    /// @notice The Paying Agent reads the coupon before paying.
    function amountPerUnitOf(uint256 period) external view returns (uint256) {
        return coupons[period].amountPerUnit;
    }

    /// @notice Cash needed to pay the period (zero until both snapshot and coupon are set).
    function totalDueOf(uint256 period) external view returns (uint256) {
        return coupons[period].totalUnits * coupons[period].amountPerUnit;
    }

    function resetHashOf(uint256 period) external view returns (bytes32) {
        return coupons[period].resetHash;
    }

    function transferHashOf(uint256 period) external view returns (bytes32) {
        return coupons[period].transferHash;
    }

    function isPaid(uint256 period) external view returns (bool) {
        return coupons[period].paid;
    }
}
