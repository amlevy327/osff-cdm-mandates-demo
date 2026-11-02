# osff-cdm-mandates-demo: mandates + coupon servicing on EAS.
# Every target runs a numbered script in script/. See README.md for the walkthrough.

-include .env

# .env may wrap values in quotes (forge's own .env reader prefers that). Make keeps quotes as
# part of the value, so strip them here. Values given on the command line still win.
MNEMONIC        := $(strip $(subst ',,$(subst ",,$(MNEMONIC))))
SEPOLIA_RPC_URL := $(strip $(subst ',,$(subst ",,$(SEPOLIA_RPC_URL))))

# No .env needed to read a deployment: fall back to a public Sepolia RPC.
PUBLIC_RPC      := https://ethereum-sepolia-rpc.publicnode.com
ifeq ($(SEPOLIA_RPC_URL),)
SEPOLIA_RPC_URL := $(PUBLIC_RPC)
endif

DEPLOYMENT ?= sepolia
PERIOD     ?= 1
RPC        ?= $(SEPOLIA_RPC_URL)
export

# Dry run: a local copy (fork) of Sepolia, with the real EAS, funded test accounts and no faucet.
# It runs under chain id 31337 so its records never mix with real Sepolia runs (11155111).
FORK_RPC       ?= $(PUBLIC_RPC)
ANVIL_PORT     ?= 8545
ANVIL_MNEMONIC := test test test test test test test test test test test junk

# --skip-simulation: gas comes from the network (eth_estimateGas), not forge's local EVM.
# Needed since Sepolia's 2026-10-06 upgrade repriced state creation, which Foundry 1.8.7 does not model yet.
# Recipes read "$$RPC" from the environment and start with @, so the RPC URL (which may carry an
# API key) is never echoed, not even by `make -n`.
BROADCAST = forge script --rpc-url "$$RPC" --broadcast --slow --skip-simulation
READ      = forge script --rpc-url "$$RPC"

# Pinned dependencies (what the tests and the Sepolia run used)
FORGE_STD_REF := v1.17.0
OZ_REF        := v5.3.0
EAS_REF       := e6e970286ff18bbdfc5d8eff2742c5ece46040e4

.PHONY: help install build test setup deploy appoint accept snapshot set-coupon fund pay failures trace \
        mandates coupon demo dry-run fail-onchain clean-dry-run check-env check-rpc

help:
	@echo "Trace our demo (no keys, no .env):"
	@echo "  make trace                 read back and link everything on Sepolia"
	@echo "  make failures              simulate parties acting outside their mandate"
	@echo "Try it locally (no keys, no faucet):"
	@echo "  make install               fetch the pinned dependencies into lib/"
	@echo "  make test                  run the contract tests"
	@echo "  make dry-run               full demo on a local fork of Sepolia"
	@echo "Deploy your own on Sepolia (needs .env):"
	@echo "  make check-env             check .env without printing secrets"
	@echo "  make demo DEPLOYMENT=mine  deploy, appoint, accept, pay period 1"
	@echo "  make fail-onchain DEPLOYMENT=mine   one real failed tx: Calc Agent calls pay()"
	@echo "  make coupon PERIOD=2 DEPLOYMENT=mine   pay the next coupon with the same mandates"

install:
	@if [ -d lib/forge-std/src ] && [ -d lib/openzeppelin-contracts/contracts ] && [ -d lib/eas-contracts/contracts ]; then \
	  echo "install: lib/ already has all three dependencies"; else \
	  forge install --no-git foundry-rs/forge-std@$(FORGE_STD_REF) OpenZeppelin/openzeppelin-contracts@$(OZ_REF) \
	    ethereum-attestation-service/eas-contracts@$(EAS_REF); fi

build:
	forge build

test:
	forge test

# ---- Numbered steps ----
setup:      check-env ; @$(BROADCAST) script/00_Setup.s.sol
deploy:     check-env ; @$(BROADCAST) script/01_Deploy.s.sol
appoint:    check-env ; @$(BROADCAST) script/02_Appoint.s.sol
accept:     check-env ; @$(BROADCAST) script/03_Accept.s.sol
snapshot:   check-env ; @$(BROADCAST) script/04_Snapshot.s.sol
set-coupon: check-env ; @$(BROADCAST) script/05_SetCoupon.s.sol
fund:       check-env ; @$(BROADCAST) script/06_Fund.s.sol
pay:        check-env ; @$(BROADCAST) script/07_Pay.s.sol
failures:   check-rpc ; @$(READ) script/08_FailureCases.s.sol
trace:      check-rpc ; @$(READ) script/09_Trace.s.sol

# Checks run before anything touches a network. They never print the RPC URL or the mnemonic.
check-rpc:
	@case "$$RPC" in http://*|https://*) ;; \
	  *) echo "check-env: SEPOLIA_RPC_URL must be a full URL (https://...), not a bare API key."; exit 1;; esac
	@[ -f deployments/$(DEPLOYMENT).json ] || case "$(MAKECMDGOALS)" in *trace*|*failures*) \
	  echo "check-env: deployments/$(DEPLOYMENT).json not found. Run make demo first, or set DEPLOYMENT."; exit 1;; esac

check-env: check-rpc
	@[ -n "$$MNEMONIC" ] || { echo "check-env: MNEMONIC is empty. Copy .env.example to .env and fill it in."; exit 1; }
	@n=$$(echo "$$MNEMONIC" | wc -w | tr -d ' '); [ "$$n" = 12 ] || [ "$$n" = 24 ] || \
	  { echo "check-env: MNEMONIC has $$n words, expected 12 or 24."; exit 1; }
	@cast wallet address --mnemonic "$$MNEMONIC" --mnemonic-index 0 >/dev/null 2>&1 || \
	  { echo "check-env: MNEMONIC is not a valid phrase. Check the spelling of each word."; exit 1; }
	@[ "$(DEPLOYMENT)" != "sepolia" ] || [ ! -f deployments/sepolia.json ] || \
	  [ "$$(cast wallet address --mnemonic "$$MNEMONIC" --mnemonic-index 0 | tr A-F a-f)" = \
	    "$$(sed -n 's/.*"issuer": *"\(0x[0-9a-fA-F]*\)".*/\1/p' deployments/sepolia.json | tr A-F a-f)" ] || \
	  { echo "check-env: deployments/sepolia.json is our demo, and your MNEMONIC is not its issuer."; \
	    echo "           Deploy your own copy under another name, e.g.  make demo DEPLOYMENT=mine"; exit 1; }

# ---- Groups ----
mandates: setup deploy appoint accept
coupon:   snapshot set-coupon fund pay failures trace
demo:     mandates coupon

# One real failed transaction for the trace: the Calc Agent (mnemonic index 2) calls pay().
# A fixed gas limit skips estimation, so the tx is sent and reverts on-chain with NotMandated.
SERVICER = $$(sed -n 's/.*"couponServicer": *"\(0x[0-9a-fA-F]*\)".*/\1/p' deployments/$(DEPLOYMENT).json)
ZERO32   = 0x0000000000000000000000000000000000000000000000000000000000000000

fail-onchain: check-env
	@cast send $(SERVICER) "pay(uint256,bytes32)" $(PERIOD) $(ZERO32) \
		--rpc-url "$$RPC" --mnemonic "$$MNEMONIC" --mnemonic-index 2 --gas-limit 150000 || true

# ---- Dry run on a local fork of Sepolia ----
dry-run:
	@anvil --fork-url $(FORK_RPC) --port $(ANVIL_PORT) --chain-id 31337 --silent & echo $$! > .anvil.pid; sleep 4
	@$(MAKE) --no-print-directory demo RPC=http://127.0.0.1:$(ANVIL_PORT) DEPLOYMENT=dry-run MNEMONIC="$(ANVIL_MNEMONIC)" \
		|| (kill $$(cat .anvil.pid); rm -f .anvil.pid; exit 1)
	@$(MAKE) --no-print-directory fail-onchain RPC=http://127.0.0.1:$(ANVIL_PORT) DEPLOYMENT=dry-run MNEMONIC="$(ANVIL_MNEMONIC)"
	@$(MAKE) --no-print-directory coupon PERIOD=2 RPC=http://127.0.0.1:$(ANVIL_PORT) DEPLOYMENT=dry-run MNEMONIC="$(ANVIL_MNEMONIC)" \
		|| (kill $$(cat .anvil.pid); rm -f .anvil.pid; exit 1)
	@kill $$(cat .anvil.pid); rm -f .anvil.pid
	@echo "Dry run complete (period 1 and period 2). Nothing was sent to Sepolia."

clean-dry-run:
	rm -f deployments/dry-run.json .anvil.pid; rm -rf broadcast/*/31337
