
import re

file_path = r'c:\Users\R.A LAPTOPS\OneDrive\Desktop\EtherShare Backup\FYP-EtherShare\blockchain_fyp\lib\channel_page.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

start_line = 4374 # 0-indexed, so line 4375
end_line = 4884   # 0-indexed

depth = 0
for i in range(start_line, end_line):
    line = lines[i]
    # Remove comments
    line = re.sub(r'//.*', '', line)
    
    for char in line:
        if char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            
print(f"Depth at end of range: {depth}")
