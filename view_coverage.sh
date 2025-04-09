#!/bin/bash

# Generate the coverage report
forge coverage --report lcov
genhtml -o coverage lcov.info --ignore-errors category

# Open the coverage report in the default browser
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    open coverage/index.html
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    xdg-open coverage/index.html
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    # Windows
    start coverage/index.html
else
    echo "Could not detect OS. Please open coverage/index.html manually."
fi

echo "Coverage report generated in ./coverage/index.html"
