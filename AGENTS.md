# AGENTS.md

Instructions for a coding agent (Claude Code, Codex, Cursor, and similar) working in this repo. Humans: see [README.md](README.md).

## What this repo is

A testnet demo of on-chain **mandates**: an issuer appoints a Registrar, a Calculation Agent and a Paying Agent through EAS attestations, each agent accepts, and a coupon is paid by a `CouponServicer` that checks `IMandateVerifier.isMandated(agent, servicer, role)` before every servicing step. [TRACE.md](TRACE.md) shows a completed run on Sepolia.

## Hard rules

1. **Never print, log, echo or paste the `MNEMONIC` or the `SEPOLIA_RPC_URL`.** The RPC URL often contains an API key. Do not `cat .env`, do not `source .env` and echo variables, do not run `make -n` and show its output, do not add these values to commands you display. To check `.env`, run `make check-env DEPLOYMENT=<name>`: it validates both values and prints only a pass or a plain error.
2. **Never ask the user to paste a mnemonic or key into the chat.** If one is needed, ask the user to create `.env` themselves (see "Deploy a new copy").
3. **Never use the deployment name `sepolia`.** `deployments/sepolia.json` is the authors' demo. Always pass `DEPLOYMENT=<another name>` for anything that signs. `make` refuses to overwrite `sepolia.json` with a different issuer, so if you see that error, change the name. Do not work around it.
4. **Never commit `.env`.** It is in `.gitignore`.
5. **Testnet only.** Do not point this at a mainnet RPC. `MockUSDC` can be minted by anyone.
6. **Run commands from the repo root.** Every path in the Makefile and scripts is relative to it.

## Prerequisites

- Foundry **1.8.7 or newer**: `forge --version`. If it is older or missing, ask the user before running `foundryup`, because it changes their machine-wide install.
- `make`, and network access to GitHub (for `make install`) and to a Sepolia RPC.

## Task: verify the repo works (no keys, no funds)

```sh
make install     # pinned deps into lib/ (skips if already present)
make test        # expect: 37 tests passed, 0 failed
make dry-run     # local fork of Sepolia; takes a few minutes
make clean-dry-run
```

Success for `make dry-run`: the output ends with `Dry run complete (period 1 and period 2). Nothing was sent to Sepolia.`, every mandate shows `Active`, every hash line shows `MATCHES`, and the one `cast send` shows `status 0 (failed)`. That failure is intended.

## Task: trace the authors' demo (no keys)

```sh
make trace       # reads deployments/sepolia.json from the chain
make failures    # simulated; nothing is sent
```

No `.env` is needed: with no `SEPOLIA_RPC_URL`, the Makefile uses `https://ethereum-sepolia-rpc.publicnode.com`. Expect three `Active` mandates, `Paid true`, and two `MATCHES` lines.

## Task: deploy a new copy on Sepolia

Pick a deployment name, for example `mine`, and use it in every command below.

1. **Ask the user** to create `.env` in the repo root from `.env.example`, with:
   - `SEPOLIA_RPC_URL="https://..."`: a full URL, never a bare API key.
   - `MNEMONIC="twelve words ..."`: a **new** phrase from `cast wallet new-mnemonic`, which the user runs in their own terminal.

   Do not create or read the file yourself.
2. Run `make check-env DEPLOYMENT=mine`. If it fails, relay the one-line message to the user. It never contains a secret.
3. **Get the issuer address** for the user to fund. This prints only the address:
   ```sh
   make -s -f - addr <<'EOF'
   -include .env
   MNEMONIC := $(subst ",,$(MNEMONIC))
   export
   addr:
   	@cast wallet address --mnemonic "$$MNEMONIC" --mnemonic-index 0
   EOF
   ```
   Ask the user to send about **0.1 Sepolia ETH** to that address from a faucet, then confirm the balance with `cast balance <address> --rpc-url https://ethereum-sepolia-rpc.publicnode.com --ether`.
4. Run, in order, checking each one before the next:
   ```sh
   make demo DEPLOYMENT=mine
   make fail-onchain DEPLOYMENT=mine
   ```
   `make demo` runs steps 00 to 09 and takes several minutes, because it waits for each transaction to confirm. Success looks like `ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.` after each broadcast step, then `Active` x3, `Paid true`, and `MATCHES` x2 in the trace. `fail-onchain` must show `status 0 (failed)`, which is intended.
5. Optional, the next coupon: `make coupon PERIOD=2 DEPLOYMENT=mine`.
6. Report back to the user: the contents of `deployments/mine.json` (addresses only, no secrets) and the links printed by step 09.

To rerun a single step, use its target (`setup`, `deploy`, `appoint`, `accept`, `snapshot`, `set-coupon`, `fund`, `pay`, `failures`, `trace`) with the same `DEPLOYMENT` and `PERIOD`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `check-env: ... not a bare API key` | `SEPOLIA_RPC_URL` is just the key | Ask the user to write the full URL, e.g. `https://sepolia.infura.io/v3/<key>` |
| `check-env: MNEMONIC has N words` or `not a valid phrase` | A word is missing or misspelled | Ask the user to fix `.env`. Do not ask for the phrase |
| `check-env: deployments/sepolia.json is our demo` | No `DEPLOYMENT` given | Add `DEPLOYMENT=<your name>` |
| A transaction fails with out of gas | Forge simulated gas locally instead of asking the network | Make sure the broadcast went through `make` (it adds `--skip-simulation`) and Foundry is 1.8.7 or newer |
| `insufficient funds` | Issuer ran out of Sepolia ETH | Ask the user to fund the issuer again |
| `AlreadyPaid`, `CouponAlreadySet`, `SnapshotAlreadyRecorded` | That step already ran for this period | Move on, or use the next `PERIOD` |
| `NotMandated(caller, role)` on a step other than `fail-onchain` | Mandates not appointed or accepted for this deployment | Run `make appoint` then `make accept` with the same `DEPLOYMENT` |
| `deployments/<name>.json not found` | Nothing deployed under that name | Run `make demo DEPLOYMENT=<name>` first |

## Where things are

- Contracts: `src/` (the interface is `src/interfaces/IMandateVerifier.sol`).
- One script per step: `script/00_Setup.s.sol` … `script/09_Trace.s.sol`. Shared config, actors and the deployment file live in `script/Base.s.sol`.
- Actors are mnemonic indexes: 0 issuer (also the contract admin), 1 registrar, 2 calculation agent, 3 paying agent, 4 to 6 holders (never sign).
- Sample CDM files whose `keccak256` goes on-chain: `cdm/`.
- Deployment output: `deployments/<name>.json`. Broadcast records: `broadcast/<script>/<chainId>/`.
