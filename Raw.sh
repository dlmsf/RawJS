#!/bin/bash

# Raw.sh - Compile and link all .asm files using NASM and LD

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting compilation and linking of .asm files...${NC}"

# Determine current architecture
ARCH=""
case "$(uname -m)" in
    "x86_64"|"amd64")
        ARCH="x86_64"
        FORMAT="elf64"
        ;;
    "i386"|"i486"|"i586"|"i686")
        ARCH="i386"
        FORMAT="elf32"
        ;;
    "arm"|"armv7l"|"armv8l"|"aarch64"|"arm64")
        ARCH="arm"
        FORMAT="elf32"
        ;;
    *)
        echo -e "${RED}Unsupported architecture: $(uname -m)${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}Detected architecture: ${ARCH} (using ${FORMAT} format)${NC}"

# Set up NASM binary path
NASM_BINARY="./._/nasm/${ARCH}-linux/nasm-${ARCH}-linux"

# Check if NASM binary exists
if [ ! -f "$NASM_BINARY" ]; then
    echo -e "${RED}NASM binary not found at: $NASM_BINARY${NC}"
    exit 1
fi

echo -e "${GREEN}Using NASM binary: $NASM_BINARY${NC}"

# Make NASM binary executable
chmod +x "$NASM_BINARY" 2>/dev/null || echo "Could not make NASM executable"

# Clean up old /dev directory and create brand new
echo -e "${BLUE}Cleaning up and creating new /dev directory...${NC}"
rm -rf "./dev"
mkdir -p "./dev"

# Create directory structure
echo -e "${BLUE}Creating directory structure...${NC}"
find "./._" -type d 2>/dev/null | while IFS= read -r dir; do
    # Skip the nasm directory and its contents
    if [[ "$dir" == "./._/nasm"* ]]; then
        continue
    fi
    
    # Create corresponding directory in /dev
    new_dir="${dir/.\/._/.\/dev}"
    mkdir -p "$new_dir" 2>/dev/null || true
done

# Find all .asm files
echo -e "${BLUE}Finding .asm files...${NC}"
ASM_FILES=$(find "./._" -name "*.asm" ! -path "./._/nasm/*" 2>/dev/null)
COUNT=$(echo "$ASM_FILES" | wc -l)

if [ "$COUNT" -eq 0 ]; then
    echo -e "${RED}No .asm files found!${NC}"
    exit 1
fi

echo -e "${YELLOW}Found $COUNT .asm files to process${NC}"

# Now compile and link all .asm files
echo -e "${BLUE}\nCompiling and linking .asm files...${NC}"

# Initialize counters
total_files=0
compiled_files=0
failed_files=0

# Use process substitution to avoid pipe issues with variable scope
while IFS= read -r asm_file; do
    ((total_files++))
    
    echo -e "\n${YELLOW}[${total_files}] Processing: ${asm_file}${NC}"
    
    # Generate output paths
    output_file="${asm_file/.\/._/.\/dev}"
    output_file="${output_file%.asm}"  # Remove .asm extension
    object_file="${output_file}.o"
    
    # Ensure output directory exists
    mkdir -p "$(dirname "$output_file")" 2>/dev/null || true
    
    # Step 1: Compile with NASM
    echo -e "  Compiling: $NASM_BINARY -f ${FORMAT} \"${asm_file}\" -o \"${object_file}\""
    "$NASM_BINARY" -f "$FORMAT" "$asm_file" -o "$object_file"
    NASM_EXIT=$?
    
    if [ $NASM_EXIT -eq 0 ]; then
        echo -e "  ${GREEN}✓ Compilation successful${NC}"
    else
        echo -e "${RED}  ✗ Compilation failed for: ${asm_file}${NC}"
        rm -f "$object_file" 2>/dev/null || true
        ((failed_files++))
        continue
    fi
    
    # Step 2: Link with LD
    echo -e "  Linking: ld \"${object_file}\" -o \"${output_file}\""
    ld "$object_file" -o "$output_file" 2>&1
    LD_EXIT=$?
    
    if [ $LD_EXIT -eq 0 ]; then
        echo -e "  ${GREEN}✓ Linking successful${NC}"
        chmod +x "$output_file" 2>/dev/null || true
        ((compiled_files++))
    else
        echo -e "${RED}  ✗ Linking failed for: ${asm_file}${NC}"
        ((failed_files++))
    fi
    
    # Step 3: Clean up object file
    rm -f "$object_file" 2>/dev/null || true
    echo -e "  ${BLUE}✓ Cleaned up object file${NC}"
    
done < <(echo "$ASM_FILES")

# Summary
echo -e "\n${BLUE}=== Compilation Summary ===${NC}"
echo -e "${GREEN}Successfully compiled and linked: ${compiled_files} files${NC}"
if [ $failed_files -gt 0 ]; then
    echo -e "${RED}Failed: ${failed_files} files${NC}"
fi
echo -e "Total .asm files processed: ${total_files}"
echo -e "${GREEN}Output directory: ./dev${NC}"

# Display what's in /dev with tree-like structure
echo -e "\n${BLUE}=== /dev Directory Structure ===${NC}"
echo -e "${GREEN}Executable files created:${NC}"

# Use a simple tree display
list_files() {
    local indent="$1"
    local dir="$2"
    
    for item in "$dir"/*; do
        if [ -d "$item" ]; then
            echo -e "${indent}└── $(basename "$item")/"
            list_files "    $indent" "$item"
        elif [ -f "$item" ]; then
            if [ -x "$item" ]; then
                echo -e "${indent}└── ${GREEN}$(basename "$item") ✓${NC}"
            else
                echo -e "${indent}└── $(basename "$item")"
            fi
        fi
    done
}

# Start listing from ./dev
for item in ./dev/*; do
    if [ -d "$item" ]; then
        echo "└── $(basename "$item")/"
        list_files "    " "$item"
    elif [ -f "$item" ]; then
        if [ -x "$item" ]; then
            echo -e "└── ${GREEN}$(basename "$item") ✓${NC}"
        else
            echo "└── $(basename "$item")"
        fi
    fi
done

# Verify all files were created
echo -e "\n${BLUE}=== Verification ===${NC}"
echo -e "Expected files: $COUNT"
echo -e "Created files: $(find "./dev" -type f 2>/dev/null | wc -l)"

if [ "$COUNT" -eq "$(find "./dev" -type f 2>/dev/null | wc -l)" ]; then
    echo -e "${GREEN}✓ All files were successfully created!${NC}"
else
    echo -e "${YELLOW}⚠ Some files might be missing${NC}"
fi

echo -e "\n${GREEN}Build completed successfully!${NC}"
echo -e "All binaries are available in the ./dev directory"