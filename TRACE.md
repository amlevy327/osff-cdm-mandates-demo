# Trace: the live demo on Sepolia

Everything below happened on the public Sepolia testnet on 2026-10-31. Every link opens a block explorer, so anyone can check each step without trusting us. Run `make trace` to read the same facts back from the chain yourself.

- Network: Sepolia (chain id 11155111)
- Attestation service: the canonical EAS deployment on Sepolia ([EAS](https://sepolia.etherscan.io/address/0xC2679fBD37d54388Ce493F1DB75320D236e1815e), [SchemaRegistry](https://sepolia.etherscan.io/address/0x0a7E2Ff54e76B8E6659aedc9103FB21c038050D0))
- Addresses and schema ids are also in `deployments/sepolia.json`. Every transaction is in `broadcast/*/11155111/run-latest.json`.

## The actors

| Role | Address | Signs? |
|---|---|---|
| Issuer (admin, appoints agents, funds the coupon) | [0x394D…1187](https://sepolia.etherscan.io/address/0x394D1d25DcC8d314380411c3b41a68449E011187) | yes |
| Registrar | [0x03f4…c62B](https://sepolia.etherscan.io/address/0x03f43686B9cA6A85a0Ce49F0823d8B1CAB4dc62B) | yes |
| Calculation Agent | [0x7998…8d50](https://sepolia.etherscan.io/address/0x7998109bdeDb6405037D5C125ae90579D5748d50) | yes |
| Paying Agent | [0x2d17…0964](https://sepolia.etherscan.io/address/0x2d1706fBEcec011aB922F560aCDcCc661aBD0964) | yes |
| Holder A (100 units) | [0x1431…d9d4](https://sepolia.etherscan.io/address/0x14318c5C681d94A05257d7c7A26dc0324922d9d4) | never |
| Holder B (250 units) | [0x3a41…194c](https://sepolia.etherscan.io/address/0x3a412CF2C9e869bd79204844497da834f8dC194c) | never |
| Holder C (650 units) | [0xf739…1Bb2](https://sepolia.etherscan.io/address/0xf739a656bBbc901960e7D6c1536b6355D7e01Bb2) | never |

## The contracts we deployed

| Contract | What it does | Address |
|---|---|---|
| MockUSDC | Test cash (6 decimals). Anyone can mint; testnet only | [0xeF4D…0C8B](https://sepolia.etherscan.io/address/0xeF4D4fc513c1F80ccCAD5C3863535dB32a4e0C8B) |
| MandateResolver | Gate on the mandate schema: only the bond's issuer can appoint, only to a known role | [0xEd1B…7c88](https://sepolia.etherscan.io/address/0xEd1B74b0c9f4D52a9656B82908393307BaAf7c88) |
| AcceptanceResolver | Gate on the acceptance schema: only the appointee can accept, and only the agreement it was appointed under | [0x6256…4cd8](https://sepolia.etherscan.io/address/0x62569549B4e7F709352cf64C25BB7BAE01a34cd8) |
| EASMandateVerifier | Implements `IMandateVerifier.isMandated(agent, servicer, role)` by re-checking both attestations on EAS | [0x11db…5aAf](https://sepolia.etherscan.io/address/0x11db54Eb3c749f2281BEbf9047e41a727B035aAf) |
| CouponServicer | The bond's servicing contract. Each write asks the verifier first | [0x133A…b5EF](https://sepolia.etherscan.io/address/0x133A750E80bB0887B98a7f172d0f7a00B034b5EF) |

| Schema | Fields | Link |
|---|---|---|
| Mandate | `string partyId, string assetId, address servicer, bytes32 role, uint64 validFrom, bytes32 agreementHash` | [easscan](https://sepolia.easscan.org/schema/view/0x47091bc35add7685166070f22e619797466913a3443fcc7497b1ffdafc3db7ee) |
| Acceptance | `bytes32 agreementHash` | [easscan](https://sepolia.easscan.org/schema/view/0xa4edc98bfafa6102b2da4d823ad495feaad99c73b85cc6ab7efa596ace1db6d8) |

## Step by step

### 00 Setup: the issuer gives each agent gas money

| Signer | What | Tx |
|---|---|---|
| Issuer | 0.01 ETH to the Registrar | [0xf128…04ed](https://sepolia.etherscan.io/tx/0xf128454744aec0de06811b5f4acd18a6dfa55f6ae4d69c56bc3f12ded6d504ed) |
| Issuer | 0.01 ETH to the Calculation Agent | [0x1608…d740](https://sepolia.etherscan.io/tx/0x16085f131559c64029292dec4ece5c78012a59b23d33e73ca78e6959387fd740) |
| Issuer | 0.01 ETH to the Paying Agent | [0x0f2a…fce3](https://sepolia.etherscan.io/tx/0x0f2a8b40e5db170a822e3e01e52d179bcd51070861681abd3b9574fecf36fce3) |

### 01 Deploy: five contracts and two schemas

| Signer | What | Tx |
|---|---|---|
| Issuer | Deploy MockUSDC | [0x2cb4…cb74](https://sepolia.etherscan.io/tx/0x2cb4fe1cf49f1e0da661d29f776ea62da6076ada52fd5865f11a816b5462cb74) |
| Issuer | Deploy MandateResolver | [0x68ab…94ce](https://sepolia.etherscan.io/tx/0x68aba459774bf7c03a8a48a7231fcdd774d5c519595b06e242be18db4d5094ce) |
| Issuer | Register the mandate schema (resolver = MandateResolver, revocable) | [0x650e…f218](https://sepolia.etherscan.io/tx/0x650ec53ee060b65022dbe64e70992811fb2090b4382d2e0d9c96055a1942f218) |
| Issuer | Deploy AcceptanceResolver | [0x3569…4f63](https://sepolia.etherscan.io/tx/0x35695d6a9431b3c2ea1c29813334da98ebfa782381926b62c3312576ca524f63) |
| Issuer | Register the acceptance schema (resolver = AcceptanceResolver, revocable) | [0x2b00…8768](https://sepolia.etherscan.io/tx/0x2b00b9c83174abae84feefa117ece40e5638905485d78cbbc8a6b8c473868768) |
| Issuer | Deploy EASMandateVerifier | [0x7bba…fb65](https://sepolia.etherscan.io/tx/0x7bba8a397b788d07d6c8d75dbfeaebeb41e667f16d54d48a552e530db652fb65) |
| Issuer | Deploy CouponServicer (issuer = admin, verifier = EASMandateVerifier, cash = MockUSDC) | [0x0625…330d](https://sepolia.etherscan.io/tx/0x0625ef9bed55542817b057b5f4b34570a96ced00fad6ffc2ae290ea8e833330d) |

### 02 Appoint and 03 Accept: three mandates, each counter-attested

The issuer appoints each agent with a mandate attestation. Then each agent signs its own acceptance, which points at the mandate (`refUID`). The verifier only says yes when both exist, neither is revoked, and the mandate is in force.

All three mandates carry `agreementHash = 0xaf94f981…feeca`, the keccak256 of `cdm/paying-agency-agreement.json`, and the asset id `ISIN:XS1234567890`. They are valid for one year.

| Agent | Mandate (signed by the issuer) | Acceptance (signed by the agent) | Status now |
|---|---|---|---|
| Registrar (`REGISTRAR`) | [attestation](https://sepolia.easscan.org/attestation/view/0xf3aecdf586df0f1270aac974a3fda9e6b6fd336036338f569adb1d926ac15647) · [tx](https://sepolia.etherscan.io/tx/0xc68544cc0ba053bf7b312602e5cf5b3c9827a50bb2959ef04f45b3fb4b78961e) | [attestation](https://sepolia.easscan.org/attestation/view/0x1e3f9c26468435e668383e9e64b0a41739b8df4533e1c47f4f5cda9c2edf014d) · [tx](https://sepolia.etherscan.io/tx/0x15335f089c46330f9f92299eee9a5d922fbf655c1a97b25aa59f1fe50d410a4b) | Active |
| Calculation Agent (`CALC_AGENT`) | [attestation](https://sepolia.easscan.org/attestation/view/0x1c3ab0dc70e621e84021ddee784c39069e4d625beff0ad3dbfdd0355edab8e4d) · [tx](https://sepolia.etherscan.io/tx/0x02cdd5f4a7996bd6ca4c23e9457921ae54e5abb0063665db0333656faaa64704) | [attestation](https://sepolia.easscan.org/attestation/view/0x7ae7520f1b3e11a8445ea90985be4b88c8c9633bb18ad794478651c908829b21) · [tx](https://sepolia.etherscan.io/tx/0x1be55e5f749f3ae5048b1705e6af8f669aec1c2b17b582ada2c11d7b2819d008) | Active |
| Paying Agent (`PAYING_AGENT`) | [attestation](https://sepolia.easscan.org/attestation/view/0x8a15330104319e90f05ae4239f8501de5b5d8b0fa44ebf3f3034fed393812e7b) · [tx](https://sepolia.etherscan.io/tx/0x9579294f060a018741bee039717b57127c15084ec8521be4b933f895cc9603d9) | [attestation](https://sepolia.easscan.org/attestation/view/0x663c71dfcbc2e301e600a47699f32a419f925dc316d4765ca2644e922147b659) · [tx](https://sepolia.etherscan.io/tx/0xb7f0809ff6dd584b69c8c5d4efd763569b30e5edb8d2c7a35796a6777f4a72aa) | Active |

### 04–07 Coupon, period 1: each step signed by the agent mandated for it

| Step | Signer (mandate checked) | What | Tx |
|---|---|---|---|
| 04 Snapshot | Registrar (`REGISTRAR`) | `recordSnapshot(1, …)`: holders A/B/C with 100/250/650 units, 1,000 total | [0x99e1…f383](https://sepolia.etherscan.io/tx/0x99e15cd0d7a4085b25f058e3f96c11877f1ba210b00a7019f7299a429608f383) |
| 05 Set coupon | Calculation Agent (`CALC_AGENT`) | `setCoupon(1, …)`: rate 5.2%, 26 mUSDC per unit, `resetHash` = hash of `cdm/period-1/reset.json` | [0xb9f2…752c](https://sepolia.etherscan.io/tx/0xb9f2549163e9c031836a5fa224c5d8694a05dc76ee45f2200225c933fdf2752c) |
| 06 Fund | Issuer (no mandate needed, this is the issuer's own cash) | Mint 26,000 mUSDC to itself ([tx](https://sepolia.etherscan.io/tx/0x80dad249d39722b5d9727f878e2ae793f4f274117c705a2eeca47094612e291e)), then transfer exactly the amount due into the servicer | [0xf837…2a0a](https://sepolia.etherscan.io/tx/0xf837d6e9ff1663dd2af2d97356fb82e66f7c7554eb437e3d3e5d079f60892a0a) |
| 07 Pay | Paying Agent (`PAYING_AGENT`) | `pay(1, transferHash)`: the contract pays each holder from its own balance. `transferHash` = hash of `cdm/period-1/transfer.json` | [0x34c3…629d](https://sepolia.etherscan.io/tx/0x34c3c3c81526cbb5f565fea07361b362b07bb5b6019c567e6fbc761a61ee629d) |

Result, read back from the chain by `make trace`:

| Check | Value |
|---|---|
| Total due | 26,000 mUSDC (1,000 units × 26) |
| Paid | true |
| `resetHash` on-chain | `0xc52c5846…1781c`, **matches** `cdm/period-1/reset.json` |
| `transferHash` on-chain | `0x8f7bc1a3…cad1e`, **matches** `cdm/period-1/transfer.json` |
| Holder A | 2,600 mUSDC |
| Holder B | 6,500 mUSDC |
| Holder C | 16,900 mUSDC |

### 08 What a missing mandate looks like

**One real failed transaction.** The Calculation Agent tries to pay the coupon. It holds a mandate, but for `CALC_AGENT`, not `PAYING_AGENT`. The servicer asks the verifier, gets `false`, and reverts. Etherscan shows the transaction as **Fail**, and the revert data decodes to `NotMandated(0x7998…8d50, PAYING_AGENT)`.

| Signer | What | Result | Tx |
|---|---|---|---|
| Calculation Agent | `pay(1, 0x00…)` | status 0, reverted `NotMandated(caller, role)` | [0x946c…acc1](https://sepolia.etherscan.io/tx/0x946cd30e17203779b50ea5e21d9f468400e85d3597f714b198be08b1222aacc1) |

**Four more cases, simulated** (`make failures`; nothing is sent, so they cost nothing). All revert with `NotMandated`:

| Caller | Calls | Needs | Caller's status for that role |
|---|---|---|---|
| Calculation Agent | `pay()` | `PAYING_AGENT` | NoMandate |
| Registrar | `setCoupon()` | `CALC_AGENT` | NoMandate |
| A holder | `pay()` | `PAYING_AGENT` | NoMandate |
| Issuer (contract admin) | `setCoupon()` | `CALC_AGENT` | NoMandate |

The last row is the point of the design: **admin rights are not a mandate.** The issuer controls the contract but still cannot act as an agent it never appointed and that never accepted.

## Gas on Sepolia (after its 2026-10-06 upgrade)

Sepolia now runs a newer Ethereum upgrade than mainnet, one that charges much more for creating new state (new accounts, new contracts, new storage). So the same demo used about **5.5× more gas on Sepolia** than the same transactions under mainnet's current rules.

Dollar figures use ETH = $2,253.41 (CoinGecko, 2026-10-31). Gas is the actual `gasUsed` from the receipts above.

| What | Gas on Sepolia | vs mainnet rules today | At 0.0292 gwei (mainnet price 2026-10-31) | At 1 gwei | At 10 gwei |
|---|---|---|---|---|---|
| Setup (top-ups, 5 deploys + 2 schemas, 3 mandates, 3 acceptances) | 40,051,092 | 5.8× | $2.64 | $90.25 | $902.52 |
| Period 1 (snapshot, set coupon, fund, pay) | 2,589,687 | 3.0× | $0.17 | $5.84 | $58.36 |
| Failed tx | 27,942 | 0.8× | <$0.01 | $0.06 | $0.63 |
| **Full demo** | **42,668,721** | **5.5×** | **$2.81** | **$96.15** | **$961.50** |

On Sepolia none of this is real money. The issuer started with 0.1 Sepolia ETH and has about 0.069 left, after funding 0.03 to the agents.

## Incidents during the run (kept for honesty)

- **One out-of-gas transfer before the demo:** [0x027a…f705](https://sepolia.etherscan.io/tx/0x027a8f5c531bcdbb6064566b36918654ed3991106110f61109856c531fbef705). Forge simulates gas with its own copy of the EVM. Even Foundry 1.8.7 does not yet model Sepolia's new state-creation pricing, so forge set too low a gas limit for a transfer to a fresh account (about 22k simulated, 207k actual). The fix, now in the Makefile: broadcast steps run with `--skip-simulation`, so the network itself estimates the gas.
