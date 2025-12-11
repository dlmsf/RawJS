#!/bin/bash

# nasm.sh - Compile and run a single .asm file with architecture detection

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}NASM Assembler & Runner${NC}"
echo -e "${YELLOW}Compile and run Assembly files${NC}\n"

# Check if input file is provided
if [ $# -lt 1 ]; then
    echo -e "${RED}Usage: $0 <file.asm> [args...]${NC}"
    echo -e "${YELLOW}Example: $0 hello.asm${NC}"
    echo -e "${YELLOW}Example: $0 program.asm arg1 arg2${NC}"
    exit 1
fi

ASM_FILE="$1"
shift  # Remove the first argument (file name), leaving only args for the binary
PROGRAM_ARGS="$@"

# Check if the file exists
if [ ! -f "$ASM_FILE" ]; then
    echo -e "${RED}Error: File '$ASM_FILE' not found!${NC}"
    exit 1
fi

# Check if it's an .asm file
if [[ ! "$ASM_FILE" =~ \.asm$ ]]; then
    echo -e "${RED}Error: '$ASM_FILE' is not an .asm file!${NC}"
    exit 1
fi

# Determine current architecture
ARCH=""
FORMAT=""
case "$(uname -m)" in
    "x86_64"|"amd64")
        ARCH="x86_64"
        FORMAT="elf64"
        ;;
    "i386"|"i486"|"i586"|"i686")
        ARCH="i386"
        FORMAT="elf32"
        ;;
    "arm"|"armv7l"|"armv8l")
        ARCH="arm"
        FORMAT="elf32"
        ;;
    "aarch64"|"arm64")
        ARCH="arm"
        FORMAT="elf64"
        ;;
    *)
        echo -e "${RED}Unsupported architecture: $(uname -m)${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}Detected architecture: ${ARCH} (using ${FORMAT} format)${NC}"

# Set up NASM binary path based on current script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NASM_BINARY="${SCRIPT_DIR}/${ARCH}-linux/nasm-${ARCH}-linux"

# Check if NASM binary exists
if [ ! -f "$NASM_BINARY" ]; then
    echo -e "${RED}NASM binary not found at: $NASM_BINARY${NC}"
    echo -e "${YELLOW}Expected path: $NASM_BINARY${NC}"
    echo -e "${YELLOW}Available architectures:${NC}"
    for dir in "${SCRIPT_DIR}"/*-linux; do
        if [ -d "$dir" ]; then
            arch_name=$(basename "$dir")
            echo -e "  - $arch_name"
        fi
    done
    exit 1
fi

echo -e "${GREEN}Using NASM binary: $NASM_BINARY${NC}"

# Make NASM binary executable
chmod +x "$NASM_BINARY" 2>/dev/null || echo -e "${YELLOW}Note: Could not modify NASM permissions${NC}"

# Extract base name for output files
BASENAME=$(basename "$ASM_FILE" .asm)
OUTPUT_DIR="${SCRIPT_DIR}/tmp_build"
OBJECT_FILE="${OUTPUT_DIR}/${BASENAME}.o"
BINARY_FILE="${OUTPUT_DIR}/${BASENAME}"

# Clean up previous build and create output directory
echo -e "\n${BLUE}Preparing build environment...${NC}"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Step 1: Compile with NASM
echo -e "\n${BLUE}Step 1: Compiling ${ASM_FILE}...${NC}"
echo -e "${YELLOW}Command: $NASM_BINARY -f $FORMAT \"$ASM_FILE\" -o \"$OBJECT_FILE\"${NC}"

"$NASM_BINARY" -f "$FORMAT" "$ASM_FILE" -o "$OBJECT_FILE"
NASM_EXIT=$?

if [ $NASM_EXIT -ne 0 ]; then
    echo -e "\n${RED}✗ Compilation failed!${NC}"
    echo -e "${YELLOW}Exit code: $NASM_EXIT${NC}"
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

echo -e "${GREEN}✓ Compilation successful${NC}"

# Step 2: Link with LD
echo -e "\n${BLUE}Step 2: Linking object file...${NC}"
echo -e "${YELLOW}Command: ld \"$OBJECT_FILE\" -o \"$BINARY_FILE\"${NC}"

ld "$OBJECT_FILE" -o "$BINARY_FILE" 2>&1
LD_EXIT=$?

if [ $LD_EXIT -ne 0 ]; then
    echo -e "\n${RED}✗ Linking failed!${NC}"
    echo -e "${YELLOW}Exit code: $LD_EXIT${NC}"
    echo -e "${YELLOW}Linking output:${NC}"
    ld "$OBJECT_FILE" -o "$BINARY_FILE"
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

echo -e "${GREEN}✓ Linking successful${NC}"

# Make binary executable
chmod +x "$BINARY_FILE" 2>/dev/null || echo -e "${YELLOW}Note: Could not make binary executable${NC}"

# Step 3: Clean up object file
rm -f "$OBJECT_FILE"
echo -e "${GREEN}✓ Cleaned up intermediate files${NC}"

# Step 4: Run the binary
echo -e "\n${BLUE}Step 3: Running ${BASENAME}...${NC}"
echo -e "${YELLOW}Binary: $BINARY_FILE${NC}"

if [ -n "$PROGRAM_ARGS" ]; then
    echo -e "${YELLOW}Arguments: $PROGRAM_ARGS${NC}"
fi

echo -e "\n${BLUE}========== PROGRAM OUTPUT ==========${NC}"

# Run the binary with any provided arguments
"$BINARY_FILE" $PROGRAM_ARGS
PROGRAM_EXIT=$?

echo -e "${BLUE}====================================${NC}"
echo -e "${YELLOW}Program exited with code: $PROGRAM_EXIT${NC}"

# Optional: Clean up binary after execution
echo -e "\n${BLUE}Cleaning up...${NC}"
rm -rf "$OUTPUT_DIR"
echo -e "${GREEN}✓ Cleanup complete${NC}"

echo -e "\n${GREEN}✓ Process completed successfully!${NC}"