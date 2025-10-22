# CDM EVM Framework - Smart Contracts

A proposed EVM-based implementation of the FINOS Common Domain Model for EVM-based blockchain deployment. Please note that this code is currently in active development and has NOT been audited. Do not use in production.

## Overview

This directory contains Solidity smart contracts implementing the CDM framework on Ethereum Virtual Machine (EVM) compatible blockchains.

## Project Structure

```
contracts-evm/
├── src/
│   └── base/                    # Layer 1: Foundation
│       ├── types/               # Type definitions
│       ├── libraries/           # Mathematical and utility libraries
│       ├── registry/            # Reference data registries
│       ├── access/              # Access control
│       └── interfaces/          # Contract interfaces
├── test/                        # Test suite
│   └── base/
│       ├── unit/                # Unit tests
│       ├── integration/         # Integration tests
│       ├── fuzz/                # Fuzz tests
│       └── gas/                 # Gas benchmarks
├── script/                      # Deployment scripts
└── docs/                        # Generated documentation
```
## Implemented Base Components

Base components constitute the foundational layer for the entire CDM EVM framework.
So far, they include:

1. **Core Type System**: The mapping of CDM base types to gas-optimized Solidity structs (CDMTypes, Enums)
2. **Mathematical Libraries**: Fixed-point arithmetic (FixedPoint), day count conventions (DayCount), interest rate compounding (CompoundingLib), and temporal utilities (DateTime)
3. **Product Primitives**: Interest rate calculations (InterestRate), calculation period generation (Schedule), ISDA business day conventions (BusinessDayAdjustments), rate observation schedules (ObservationSchedule), and payment calculations (Cashflow)
4. **Reference Data Registry**: Party, asset, and identifier management (CDMStaticData)
5. **Validation Layer**: Data structure validation and conditional logic enforcement (CDMValidation)
6. **Access Control**: Role-based permissions framework

---------

**Enums.sol**
- 20+ enumeration types mapping CDM types to Solidity
- Day count conventions, business day adjustments, party roles
- Price types, quantity types, identifier types
- Product taxonomies and asset classes

**CDMTypes.sol**
- 30+ struct definitions for core CDM types
- Gas-optimized field ordering
- Helper library for type creation
- Types include: Party, Identifier, Measure, Quantity, Price, AdjustableDate

Key structures:
```solidity
struct Party {
    bytes32 partyId;              // Unique identifier
    address account;              // On-chain account (20 bytes)
    PartyTypeEnum partyType;      // Packed with account (1 byte)
    bytes32 nameHash;             // Hash of party name
    bytes32 metaKey;              // Metadata reference
    PartyIdentifier[] identifiers; // External IDs (LEI, BIC)
}

struct Measure {
    uint256 value;                // Fixed-point value (18 decimals)
    UnitEnum unit;                // Unit of measure
    bytes3 currencyCode;          // ISO 4217 currency
}
```

### 2. Mathematical Libraries

**FixedPoint.sol**
- Complete fixed-point arithmetic library
- Operations: add, sub, mul, div, pow, sqrt
- Financial helpers: basis points, percentages, rounding
- Extensive overflow/underflow checks
- All core arithmetic operations <700 gas
- Financial helpers (basis points, percentages) <1,100 gas
- Complex operations (pow, rounding) remain <5,000 gas

Example operations:
```solidity
// 5% interest rate
uint256 rate = FixedPoint.fromBasisPoints(500); // 0.05e18

// Calculate interest: principal * rate
uint256 interest = principal.mul(rate);

// Apply percentage: amount * 0.15
uint256 result = amount.applyPercentage(FixedPoint.fromPercent(15));
```

**DateTime.sol**
- Unix timestamp manipulation
- Year/month/day extraction and validation
- Leap year calculations
- Date arithmetic (add days, months, years)
- Date range calculations
- Simple operations (comparisons, basic getters) are ultra-efficient
- Date extraction operations reasonable for complexity
- Month/year addition expensive due to end-of-month adjustments
- **Recommendation:**  Favor `addDays()` when possible (10x cheaper than `addMonths()`)
- **Optimization Opportunity:** Caching year start calculations
- **Optimization Opportunity:** Leap year and month-end logic in addMonths


**DayCount.sol**
- All ISDA day count conventions
- ACT/360, ACT/365, ACT/ACT ISDA, ACT/ACT ICMA
- 30/360, 30E/360, 30E/360 ISDA
- Critical for accurate interest calculations
- Handles leap years and month-end adjustments
- ACT/ACT ISDA efficient for same-year calculations
- **Recommendation:** ACT/360 and ACT/365 Fixed are ULTRA-EFFICIENT. Use when possible.
- **Warning:** 30/360 variants are EXPENSIVE (175K-360K gas)
- **Warning:** ACT/ACT ISDA cross-year calculations moderately expensive (year splitting)

Example:
```solidity
// Calculate ACT/360 day count fraction
uint256 fraction = DayCount.calculate(
    DayCountFractionEnum.ACT_360,
    startDate,     // Unix timestamp
    endDate,       // Unix timestamp
    0,             // No termination date
    0              // No frequency
);
// Returns: (actual days / 360) in fixed-point
```

**CompoundingLib.sol**
- Interest rate compounding methods
- Geometric compounding: (1+r1)*(1+r2)*...-1
- Weighted averaging
- Time-weighted averaging
- Accrual and discount factor calculations
- ALL operations <10K gas

### 3. Validation Framework (350+ lines)

**CDMValidation.sol**
- Comprehensive validation for all CDM types
- Fail-fast with descriptive errors
- Party validation (IDs, accounts, identifiers)
- Measure validation (values, currency codes)
- Date validation (ranges, ordering, business days)
- Reference and array validations
- ALL validations <5K gas 
- Read operations highly efficient (2.5K-25K gas)
- **Warning:** Write operations expensive** (100K-260K gas) - expected for storage
- **Warning:** Party registration most expensive (260K gas) due to complex struct + array storage

Example validations:
```solidity
// Validate party has required fields
CDMValidation.validateParty(party);

// Validate date range (start before end)
CDMValidation.validateDateRange(startDate, endDate);

// Validate measure has currency if unit is CURRENCY
CDMValidation.validateMeasure(measure);
```

### 4. Access Control

**CDMRoles.sol**
- Centralized role definitions (15 roles)
- Administrative roles: ADMIN, GOVERNANCE, PAUSE_GUARDIAN, UPGRADER
- Data management: PARTY_MANAGER, ASSET_MANAGER, INDEX_MANAGER
- Product & trading: PRODUCT_CREATOR, TRADE_EXECUTOR, SETTLEMENT
- Oracle roles: ORACLE_UPDATER, ORACLE_MANAGER
- Compliance: REPORTING, COLLATERAL_MANAGER

All roles use keccak256 hashing per OpenZeppelin standard:
```solidity
bytes32 public constant PARTY_MANAGER_ROLE = keccak256("PARTY_MANAGER_ROLE");
```

### 5. Static Data Registry

**CDMStaticData.sol**
- UUPS upgradeable proxy pattern
- Party registration with reverse lookups
- Asset identifier registration
- Index registration
- Role-based access control
- Pausable for emergencies
- Event emissions for all state changes

Key features:
```solidity
// Register party (only PARTY_MANAGER_ROLE)
function registerParty(Party memory party) external returns (bytes32);

// Reverse lookups
function getPartyIdByAccount(address account) external view returns (bytes32);
function getPartyIdByIdentifier(bytes32 identifier) external view returns (bytes32);

// Asset registration
function registerAsset(bytes32 assetId, Identifier memory identifier) external;

// Upgrade authorization (only UPGRADER_ROLE)
function upgradeToAndCall(address newImplementation, bytes memory data) external;
```

**ICDMStaticData.sol**
- Complete interface for CDMStaticData
- Enables type-safe contract interactions
- Documents all public functions and events

**DeployCDMStaticData.s.sol**
- Foundry deployment script
- Deploys implementation and proxy
- Initializes with admin roles
- Grants operational roles
- Supports multiple networks (testnet, mainnet)

## Security

This code is currently in active development and has NOT been audited. Do not use in production.

