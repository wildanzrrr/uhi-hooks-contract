# Makefile for StreamFund deployment

# Load environment variables
include .env
export $(shell sed 's/=.*//' .env)

# Gas settings
GAS_LIMIT = 30000000

.PHONY: help deployCore generateSalt deploySF initPool deployAll test clean anvil build fmt analyze testCoverage testCoverageReport simulateTrades

help:
		@echo "Available commands:"
		@echo "  deployCore       		- Deploy core contracts"
		@echo "  generateSalt     		- Generate salt for HookMiner"
		@echo "  deploySF         		- Deploy StreamFund contract"
		@echo "  test              		- Run tests"
		@echo "  clean             		- Clean build artifacts"
		@echo "  anvil             		- Start local Anvil node"
		@echo "  build             		- Build the project"
		@echo "  fmt               		- Format code"
		@echo "  analyze           		- Run static analysis"
		@echo "  testCoverageReport		- Generate coverage report"
		@echo "  simulateTrades    		- Simulate buy/sell trades"

# Start local Anvil node
anvil:
		@echo "Starting Anvil node..."
		anvil --host 0.0.0.0 --port 8545 --chain-id 31337

deployCore:
		@echo "Deploying Core contracts to $(RPC_URL)..."
		forge script script/DeployCore.s.sol:DeployCore \
				--rpc-url $(RPC_URL) \
				--private-key $(PRIVATE_KEY) \
				--broadcast \
				--gas-limit $(GAS_LIMIT) \
				-v

generateSalt:
		@echo "Generating salt..."
		forge script script/MineHookSalt.s.sol:MineHookSalt \ 
				--rpc-url $(RPC_URL) \
				--private-key $(PRIVATE_KEY) \
				--broadcast \
				--gas-limit $(GAS_LIMIT) \
				-v

# Deploy to network specified in .env
deploySF:
		@echo "Deploying StreamFund to $(RPC_URL)..."
		forge script script/DeployStreamFund.s.sol:DeployStreamFund \
				--rpc-url $(RPC_URL) \
				--private-key $(PRIVATE_KEY) \
				--broadcast \
				--gas-limit $(GAS_LIMIT) \
				-v

initPool:
		@echo "Deploying Mock Token and Pool to $(RPC_URL)..."
			forge script script/InitPool.s.sol:InitPool \
				--rpc-url $(RPC_URL) \
				--private-key $(PRIVATE_KEY) \
				--broadcast \
				--gas-limit $(GAS_LIMIT) \
				-v

deployAll: deployCore generateSalt deploySF initPool
		@echo "Complete StreamFund deployment finished"
								
# Run tests
test:
		@echo "Running tests..."
		forge test -v

# Clean build artifacts
clean:
		@echo "Cleaning build artifacts..."
		forge clean

# Build the project
build:
		@echo "Building project..."
		forge build

# Check code formatting
fmt:
		@echo "Formatting code..."
		forge fmt

# Run static analysis
analyze:
		@echo "Running static analysis..."
		forge test --gas-report

# Generate coverage report
testCoverageReport: 
	forge coverage --no-match-coverage '^(script|test)/' --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage --ignore-errors category --ignore-errors inconsistent --ignore-errors corrupt

# Simulate trading after deployment
simulateTrades:
		@echo "Simulating trades on $(RPC_URL)..."
		forge script script/SimulateTrades.s.sol:SimulateTrades \
				--rpc-url $(RPC_URL) \
				--private-key $(PRIVATE_KEY) \
				--broadcast \
				--gas-limit $(GAS_LIMIT) \
				-v