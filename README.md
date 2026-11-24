# InvariantKit

Solidity checks and Foundry fixtures for DeFi contracts. The Python CLI validates property definitions and converts saved Forge JSON into versioned reports.

## Run the suite

Use Foundry v1.5.1 and Python 3.10 or newer. Foundry uses Solidity 0.8.20 for the fixtures.

```sh
forge soldeer install --config-location foundry
python -m pip install '.[test]'
forge fmt --check
forge test
python -m pytest
```

The default Foundry profile runs 64 sequences of 64 calls per campaign. The `ci` profile runs 256 sequences of 128 calls. Set `FOUNDRY_PROFILE=ci` to use it. In PowerShell, set `$env:FOUNDRY_PROFILE = 'ci'`.

## Property packs

| Pack | Checks and assumptions | Foundry example |
| --- | --- | --- |
| ERC-4626 | Preview bounds, exact asset and share deltas, and caller-independent conversions. Take the preview and action in the same transaction as the same caller. | [Vault campaigns](test/invariant/VaultInvariant.t.sol) |
| Accounting | Balance changes, absolute tolerance in base units, and supply reconciliation over the full holder set. Fixtures cover fees, rebases, and transfers that return `false`. | [Token accounting](test/invariant/TokenAccounting.t.sol) |
| Oracle | Answer bounds in raw feed units, maximum age in seconds, and expected decimals. Supply these values for your protocol. | [Oracle checks](test/unit/OracleChecks.t.sol) |
| Constant-product AMM | Reserve deltas, custody, and the fee-adjusted product for a V2-style swap with one input and one output. The fee stays in the pool. | [Swap campaign](test/invariant/SwapPool.t.sol) |
| Lending | Debt changes, borrow limits, and total debt. Keep debt snapshots on a common accrual basis and valuations in the same unit. | [Lending campaign](test/invariant/LendingMarket.t.sol) |
| Access control | Ownership, membership, role admins, and rejected actions. Hash the protected fields before and after a denied call. | [Authority campaign](test/invariant/Authority.t.sol) |
| Upgradeability | Full ERC-1967 slot words, preserved application state, and initializer versions. The local fixture uses direct implementation upgrades. | [Proxy campaign](test/invariant/ProxyUpgrade.t.sol) |
| Cross-contract | Conserved assets and reported custody across an explicit holder set. Use one token per boundary and list each holder once in ascending address order. | [Vault, strategy, and treasury](test/invariant/VaultStrategyTreasury.t.sol) |

If the repository is at `lib/invariantkit` in your Foundry project, add `invariantkit/=lib/invariantkit/src/` to `remappings.txt`. The Solidity libraries under `src/` have no Foundry dependency.

```solidity
import {ERC4626Preview} from "invariantkit/erc4626/ERC4626Preview.sol";

uint256 preview = vault.previewDeposit(assets);
uint256 shares = vault.deposit(assets, receiver);
ERC4626Preview.checkDeposit(preview, shares);
```

## Export a report

```sh
forge test --json > forge.json
invariantkit report forge.json > invariantkit-report.json
invariantkit validate result invariantkit-report.json
```

`invariantkit list` prints the bundled property catalog. To use your own catalog, run `invariantkit validate definition catalog.json` and pass `--definitions catalog.json` to `report`. For a filtered Forge run, repeat `--id` for the definitions you expect to see. The catalog maps each property or fixture campaign to its Forge suite and test signature. [Bundled catalog](cli/invariantkit/data/catalog.json)

| Report status | Meaning |
| --- | --- |
| `pass` | Forge passed the test and the configured evidence checks held. |
| `fail` | Forge reported a test failure. |
| `inconclusive` | A recognized coverage gate failed or the campaign lacked required execution evidence. |
| `not_attempted` | The test was unbound, absent, or skipped. |
| `error` | Setup failed or the matching test record used an invalid shape. |

`report` exits 0 when every selected definition passes, 1 when a valid report has another outcome, and 2 when input or validation fails. Keep Forge's exit status when checking the entire suite. Its handler counts include early returns. The report preserves those counts and omits traces, calldata, and durations. The formatter reads files up to 64 MiB and supports Forge v1.5.1 JSON. [Definition schema](cli/invariantkit/schemas/definition.schema.json) · [Result schema](cli/invariantkit/schemas/result.schema.json)

## Release on GitHub

The workflow checks Solidity formatting, runs the Foundry and CLI suites, and uploads the normalized report. A push of a tag matching the package version, such as `v1.0.0`, builds and publishes the wheel after verification. [Workflow](.github/workflows/ci.yml)

For a new property, document its units and assumptions and add a local case that fails for the expected reason. Run both test suites before tagging a release. [Security reporting](SECURITY.md)
