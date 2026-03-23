#!/usr/bin/env python3
"""Update LLM prompt in main.dart to match tap_interface format"""

# Read the file
with open('lib/main.dart', 'r') as f:
    content = f.read()

# Old prompt (simplified - looking for the key distinguishing line)
old_pattern = "          'Provide up to \"${llmOptions}\" short, single-phrase options related to: \"${question}\".\\n'"

# New prompt line (matching tap_interface)
new_pattern = "          'Generate exactly \"$llmOptions\" short, single-phrase options related to: \"$question\".\\n'\n          'IMPORTANT: Provide exactly $llmOptions options, no more, no less.\\n'"

# Replace
if old_pattern in content:
    content = content.replace(old_pattern, new_pattern)
    print("✓ Replaced 'Provide up to' with 'Generate exactly'")
else:
    print("✗ Pattern not found - checking variations...")
    # Try to find it with different quote styles
    if "'Provide up to" in content:
        print("Found 'Provide up to' in content")
    else:
        print("'Provide up to' not found at all")

# Also update the format specification
old_format = "          'Format your response as a JSON list where each item has \"option\" and \"summary\" keys.\\n'"
new_format = "          'Format your response as a JSON list where each item has \"option\", \"summary\", and \"keywords\" keys.\\n'"

if old_format in content:
    content = content.replace(old_format, new_format)
    print("✓ Added 'keywords' to format specification")

# Add keywords documentation before the Example line
old_example_line = "          'Example: [{\"option\": \"...\", \"summary\": \"...\"}]';"
new_example = """          'The \"keywords\" key should be a list of 1-3 simple, concrete nouns or verbs from the phrase that could be used to find relevant images. Focus on visual, concrete concepts (like \"food\", \"happy\", \"play\", \"home\") rather than abstract words.\\n'
          'Example: [{\"option\": \"I want to go outside\", \"summary\": \"Go outside\", \"keywords\": [\"outside\", \"play\"]}, {\"option\": \"Can I have some water please?\", \"summary\": \"Water please\", \"keywords\": [\"water\", \"drink\"]}]';"""

if old_example_line in content:
    content = content.replace(old_example_line, new_example)
    print("✓ Updated example with keywords")

# Remove the [0m if it exists (escape sequence)
content = content.replace("          '[0m${summaryInstruction}\\n'\n", "          '$summaryInstruction\\n'\n")

# Write back
with open('lib/main.dart', 'w') as f:
    f.write(content)

print("\n✓ Updates complete!")
