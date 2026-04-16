#!/bin/bash

# Change to repo root (parent of scripts/)
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Run all Whisp tests
swift test 2>&1 | grep -E "(Test Case|passed|failed|error:|Executed)"
