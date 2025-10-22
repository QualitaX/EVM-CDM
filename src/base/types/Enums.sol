// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Enums
 * @notice Enumeration definitions for FINOS CDM on EVM
 * @dev Central location for all enumerations used across the CDM framework
 * @dev Maps to CDM enumeration definitions from Rosetta DSL
 *
 * @custom:security-contact security@finos.org
 * @author FINOS CDM EVM Framework Team
 */

// =============================================================================
// IDENTIFIER ENUMERATIONS
// =============================================================================

/// @notice Type of identifier
/// @dev Maps to cdm.base.staticdata.identifier.IdentifierTypeEnum
enum IdentifierTypeEnum {
    ISIN,          // International Securities Identification Number (ISO 6166)
    CUSIP,         // Committee on Uniform Securities Identification Procedures
    SEDOL,         // Stock Exchange Daily Official List
    RIC,           // Reuters Instrument Code
    BBGID,         // Bloomberg ID
    FIGI,          // Financial Instrument Global Identifier (ISO 25300)
    LEI,           // Legal Entity Identifier (ISO 17442)
    INTERNAL       // Internal system identifier
}

/// @notice Type of asset identifier
enum AssignedIdentifierTypeEnum {
    ISIN,
    CUSIP,
    SEDOL,
    FIGI,
    BBG_COMPOSITE,  // Bloomberg Composite ID
    OTHER
}

/// @notice Type of party identifier
enum PartyIdentifierTypeEnum {
    LEI,            // Legal Entity Identifier (ISO 17442)
    BIC,            // Bank Identifier Code (ISO 9362) / SWIFT code
    GLEIF,          // GLEIF Red Code
    US_EMPLOYER_ID, // US Employer Identification Number (EIN)
    INTERNAL        // Internal party identifier
}

/// @notice Source of product identifier
enum ProductIdSourceEnum {
    ISIN,
    FIGI,
    INTERNAL,
    TAXONOMY_INFERRED  // Inferred from product composition per CDM design
}

// =============================================================================
// PARTY ENUMERATIONS
// =============================================================================

/// @notice Type of party
/// @dev Maps to cdm.base.staticdata.party.PartyTypeEnum
enum PartyTypeEnum {
    NATURAL_PERSON,  // Individual person
    LEGAL_ENTITY     // Corporate entity
}

/// @notice Role of a party in a transaction
/// @dev Maps to cdm.base.staticdata.party.PartyRoleEnum
/// @dev Extensive enumeration covering all CDM-defined roles
enum PartyRoleEnum {
    // Trading roles
    BUYER,
    SELLER,
    PAYER,
    RECEIVER,

    // Calculation agent roles
    CALCULATION_AGENT_PARTY_A,
    CALCULATION_AGENT_PARTY_B,
    CALCULATION_AGENT_INDEPENDENT,
    DETERMINING_PARTY,

    // Operational roles
    BAILEE,
    CUSTODIAN,
    BROKER,
    CLEARING_ORGANIZATION,
    EXECUTION_AGENT,
    EXECUTION_FACILITY,

    // Beneficial roles
    BENEFICIARY,

    // Lending roles
    LENDER,
    BORROWER,

    // Collateral roles
    SECURED_PARTY,
    PLEDGOR,

    // Additional roles
    EXERCISE_NOTICE_RECEIVER,
    ISSUER,
    GUARANTOR,
    PRINCIPAL,
    AGENT,
    ARRANGERBUYER,
    SELLING_PARTY
}

/// @notice Type of account
enum AccountTypeEnum {
    HOUSE,             // Firm's own account (proprietary)
    CLIENT,            // Client account
    SEGREGATED_CLIENT, // Segregated client account
    NOMINEE            // Nominee account
}

// =============================================================================
// MATHEMATICAL UNIT ENUMERATIONS
// =============================================================================

/// @notice Unit of measure
/// @dev Maps to cdm.base.math.UnitEnum
enum UnitEnum {
    // Currency units
    CURRENCY,          // ISO 4217 currency code (stored separately)

    // Quantity units
    SHARES,           // Number of shares
    CONTRACTS,        // Number of contracts
    LOTS,            // Number of lots
    UNITS,           // Generic units

    // Commodity units
    BARRELS,         // Barrels (oil)
    BUSHELS,         // Bushels (agriculture)
    METRIC_TONS,     // Metric tons
    TROY_OUNCES,     // Troy ounces (precious metals)
    POUNDS,          // Pounds

    // Financial units
    BASIS_POINTS,    // Basis points (0.01%)
    PERCENTAGE,      // Percentage
    INDEX_UNITS,     // Index units

    // Time units
    DAYS,
    WEEKS,
    MONTHS,
    YEARS
}

/// @notice Type of quantity
/// @dev Maps to cdm.base.math.QuantityTypeEnum
enum QuantityTypeEnum {
    NOTIONAL,         // Notional amount
    UNIT,            // Unit quantity (shares, contracts)
    PRINCIPAL,       // Principal amount
    NUMBER_OF_UNITS  // Generic number of units
}

/// @notice Type of price
/// @dev Maps to CDM price type enumeration
enum PriceTypeEnum {
    ASSET_PRICE,      // Spot price of underlying asset
    INTEREST_RATE,    // Interest rate
    EXCHANGE_RATE,    // Foreign exchange rate
    SPREAD,          // Spread over reference rate
    MULTIPLIER,      // Multiplier factor
    DIVIDEND_RATE,   // Dividend rate
    VARIANCE,        // Variance
    VOLATILITY,      // Volatility
    INFLATION_RATE,  // Inflation rate
    CASH_PRICE,      // Cash price
    PERCENTAGE_OF_NOTIONAL // Percentage of notional
}

/// @notice Arithmetic operator for price/rate operations
enum ArithmeticOperatorEnum {
    ADD,           // Addition
    SUBTRACT,      // Subtraction
    MULTIPLY,      // Multiplication
    DIVIDE         // Division
}

/// @notice Direction for rounding
enum RoundingDirectionEnum {
    DOWN,          // Round down (floor)
    UP,            // Round up (ceiling)
    NEAREST        // Round to nearest (standard rounding)
}

/// @notice Mode for rounding
enum RoundingModeEnum {
    NONE,              // No rounding
    DECIMAL_PLACES     // Round to specified decimal places
}

// =============================================================================
// DATE/TIME ENUMERATIONS
// =============================================================================

/// @notice Business day convention for date adjustments
/// @dev Maps to cdm.base.datetime.BusinessDayConventionEnum
enum BusinessDayConventionEnum {
    NONE,                 // No adjustment
    FOLLOWING,            // Next business day
    MODIFIED_FOLLOWING,   // Next business day unless next month
    PRECEDING,            // Previous business day
    MODIFIED_PRECEDING,   // Previous business day unless previous month
    NEAREST              // Nearest business day
}

/// @notice Day count fraction convention
/// @dev Maps to cdm.base.datetime.DayCountFractionEnum
/// @dev Critical for interest calculations per ISDA definitions
enum DayCountFractionEnum {
    ACT_360,         // Actual/360 - Money market basis
    ACT_365_FIXED,   // Actual/365 Fixed
    ACT_ACT_ISDA,    // Actual/Actual ISDA (most accurate)
    ACT_ACT_ICMA,    // Actual/Actual ICMA (bond market)
    THIRTY_360,      // 30/360 Bond Basis (US corporate bonds)
    THIRTY_E_360,    // 30E/360 Eurobond Basis
    THIRTY_E_360_ISDA, // 30E/360 ISDA
    ACT_365L,        // Actual/365 Leap year
    ACT_ACT_AFB,     // Actual/Actual AFB (French)
    ONE_ONE          // 1/1 (no accrual)
}

/// @notice Business center (financial center for holiday calendars)
/// @dev Maps to cdm.base.datetime.BusinessCenterEnum
/// @dev Subset of major financial centers
enum BusinessCenterEnum {
    USNY,    // New York
    GBLO,    // London
    JPTO,    // Tokyo
    FRPA,    // Paris
    DEFR,    // Frankfurt
    CHZU,    // Zurich
    HKHK,    // Hong Kong
    SGSI,    // Singapore
    AUSY,    // Sydney
    BRSP,    // São Paulo
    CATO,    // Toronto
    NYNY,    // New York (alternate code)
    EUTA     // TARGET (Euro zone)
}

/// @notice Period unit for time intervals
/// @dev Maps to cdm.base.datetime.PeriodEnum
enum PeriodEnum {
    DAY,
    WEEK,
    MONTH,
    YEAR,
    TERM  // Entire term of the transaction
}

// =============================================================================
// TAXONOMY ENUMERATIONS
// =============================================================================

/// @notice Source of taxonomy classification
/// @dev Maps to cdm.base.staticdata.asset.TaxonomySourceEnum
enum TaxonomySourceEnum {
    ISDA,              // ISDA product taxonomy
    CFTC,              // CFTC product classifications (US)
    ESMA,              // ESMA classifications (EU)
    ANNA,              // ANNA DSB (derivatives service bureau)
    ISO,               // ISO standards
    INTERNAL           // Internal classification
}

// =============================================================================
// COMPOUNDING ENUMERATIONS
// =============================================================================

/// @notice Method for compounding rates
/// @dev Used in floating rate calculations
enum CompoundingMethodEnum {
    NONE,               // No compounding (simple rate)
    FLAT,               // Flat compounding (simple addition)
    STRAIGHT,           // Straight compounding (geometric)
    SPREAD_EXCLUSIVE    // Spread exclusive compounding
}

// =============================================================================
// STATE ENUMERATIONS
// =============================================================================

/// @notice Closed state of a trade
/// @dev Indicates why a trade was closed
enum ClosedStateEnum {
    ALLOCATED,   // Closed due to allocation
    CANCELLED,   // Cancelled
    EXERCISED,   // Closed due to option exercise
    EXPIRED,     // Expired
    MATURED,     // Reached maturity
    NOVATED,     // Novated away
    TERMINATED   // Terminated early
}

/// @notice Position status
enum PositionStatusEnum {
    EXECUTED,    // Trade executed
    SETTLED,     // Trade settled
    CANCELLED,   // Cancelled
    PENDING      // Pending
}
