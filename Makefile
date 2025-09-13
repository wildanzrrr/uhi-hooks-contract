-include .env

.PHONY: clean build test testCoverage testCoverageReport

clean:
	rm -rf cache/ \
		artifacts/ \
		out/ \
		coverage/
	 forge clean

build:
	forge build

test:
	forge test

testCoverage:
	forge coverage --no-match-coverage '^(script|test)/'

testCoverageReport: 
	forge coverage --no-match-coverage '^(script|test)/' --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage --ignore-errors category --ignore-errors inconsistent --ignore-errors corrupt