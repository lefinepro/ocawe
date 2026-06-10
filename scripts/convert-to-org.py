#!/usr/bin/env python3
"""Convert markdown files to org format."""

import os
import re
import sys


def convert_md_to_org(input_file):
    """Convert a single markdown file to org format."""
    output_file = input_file[:-3] + ".org"
    
    with open(input_file, 'r') as f:
        content = f.read()
    
    lines = content.split('\n')
    result = []
    in_code_block = False
    code_lang = ""
    
    for line in lines:
        # Check for code block markers
        code_block_match = re.match(r'^```(.*)$', line)
        if code_block_match:
            if not in_code_block:
                # Starting code block
                code_lang = code_block_match.group(1)
                result.append(f"#+begin_src {code_lang}")
                in_code_block = True
            else:
                # Ending code block
                result.append("#+end_src")
                in_code_block = False
                code_lang = ""
            continue
        
        # If inside code block, output as-is
        if in_code_block:
            result.append(line)
            continue
        
        # Convert headings: # -> **, ## -> ***, etc.
        heading_match = re.match(r'^(#{1,6})\s+(.*)$', line)
        if heading_match:
            hash_count = len(heading_match.group(1))
            heading_text = heading_match.group(2)
            stars = '*' * (hash_count + 1)
            result.append(f"{stars} {heading_text}")
            continue
        
        # Process inline formatting
        # We need to handle these carefully to avoid conflicts
        
        # Convert links: [text](url) -> [[url][text]]
        # Do this before other inline formatting
        line = re.sub(r'\[([^\]]+)\]\(([^\)]+)\)', r'[[\2][\1]]', line)
        
        # Convert inline code: `code` -> =code=
        # Handle multiple occurrences
        line = re.sub(r'`([^`]+)`', r'=\1=', line)
        
        # Convert bold: **text** -> *text*
        # Do bold before italic to avoid conflicts
        line = re.sub(r'\*\*([^\*]+)\*\*', r'*\1*', line)
        
        # Convert italic: *text* -> /text/
        # Be careful not to match * at beginning of line (org headings)
        # Only match *text* where the * is not at start of line
        line = re.sub(r'(?<!\*)\*([^\*]+)\*(?!\*)', r'/\1/', line)
        
        result.append(line)
    
    with open(output_file, 'w') as f:
        f.write('\n'.join(result))
    
    print(f"Converted: {input_file} -> {output_file}")


def main():
    if len(sys.argv) > 1:
        base_dir = sys.argv[1]
    else:
        base_dir = "/drive2/datastore/dev/lefine/ocawe/caws"
    
    # Find all .md files recursively
    for root, dirs, files in os.walk(base_dir):
        for filename in files:
            if filename.endswith('.md'):
                filepath = os.path.join(root, filename)
                convert_md_to_org(filepath)
    
    print("Conversion complete!")


if __name__ == '__main__':
    main()
