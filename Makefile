-include .env

.PHONY: help
help: # Show help for each of the Makefile recipes.
	@grep -E '^[a-zA-Z0-9 -]+:.*#'  Makefile | sort | while read -r l; do printf "\033[1;32m$$(echo $$l | cut -f 1 -d':')\033[00m:$$(echo $$l | cut -f 2- -d'#')\n"; done

.PHONY: clean
clean: # Clean the repo
	forge clean

.PHONY: install
install : # Install requirements
	forge install cyfrin/foundry-devops@0.1.1 --no-commit && \
		forge install smartcontractkit/chainlink-brownie-contracts@1.1.0 --no-commit && \
		forge install foundry-rs/forge-std@v1.8.2 --no-commit \
		forge install transmissions11/solmate

.PHONY: build
build: # Build the repo
	forge build

.PHONY: deploy-sepolia
deploy-sepolia: # Deploy contracts to Sepolia test net
ifndef SEPOLIA_RPC_URL
	$(error SEPOLIA_RPC_URL is undefined)
endif
ifndef SEPOLIA_ACCOUNT
	$(error SEPOLIA_ACCOUNT is undefined)
endif
ifndef ETHERSCAN_API_KEY
	$(error ETHERSCAN_API_KEY is undefined)
endif
	@forge script script/DeployRaffle.s.sol:DeployRaffle \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(SEPOLIA_ACCOUNT) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		-vvvv

.PHONY: deploy-anvil
deploy-anvil: # Deploy contracts to local Anvil
ifndef ANVIL_RPC_URL
	$(error ANVIL_RPC_URL is undefined)
endif
ifndef ANVIL_ACCOUNT
	$(error ANVIL_ACCOUNT is undefined)
endif
	@forge script script/DeployRaffle.s.sol:DeployRaffle \
		--rpc-url $(ANVIL_RPC_URL) \
		--account $(ANVIL_ACCOUNT) \
		--broadcast \
		-vvvv