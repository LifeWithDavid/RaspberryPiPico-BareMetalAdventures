import re

input_file = "Pico_TIM_m6502.asm"
output_file = "Pico_TIM_m6502_hex.asm"

octal_regex = re.compile(r'@([0-7]+)')

def octal_to_hex(match):
    oct_str = match.group(1)
    value = int(oct_str, 8)        # convert octal → decimal
    return f"${value:02X}"         # convert decimal → hex

with open(input_file, "r", encoding="latin-1") as f:
    content = f.read()

new_content = octal_regex.sub(octal_to_hex, content)

with open(output_file, "w", encoding="latin-1") as f:
    f.write(new_content)

print("Octal → hex conversion complete.")
