#!/usr/bin/env python3
"""Fix the wake word LLM prompt to be more strict and prevent unrelated responses."""

import re

# Read the file
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find and replace the prompt construction
old_prompt = r"""final promptForLLM =
          'Provide up to "\${llmOptions}" short, single-phrase options related to: "\${question}"\.\\n'
          'Do not include any introductory or concluding text\.\\n'
          'Do NOT number your responses \(no 1\., 2\., 3\., etc\.\)\.\\n'
          'Do NOT use bullet points or dashes\.\\n'
          'Format your response as a JSON list where each item has "option" and "summary" keys\.\\n'
          'The "option" key should contain the FULL option text\. If the option contains a question and answer, like a joke, the option contain the question and the answer\.\\n'
          '\[0m\$\{summaryInstruction\}\\n'
          'Example: \[\{"option": "\.\.\.", "summary": "\.\.\."\}\]';"""

new_prompt = r"""final promptForLLM =
          'Generate exactly $llmOptions short, single-phrase options that directly answer or respond to: "$question".\n'
          'IMPORTANT: Provide exactly $llmOptions options, no more, no less. Each option must be relevant to the question asked.\n'
          'Do NOT include any introductory text, concluding text, explanations, or unrelated information.\n'
          'Do NOT number your responses (no 1., 2., 3., etc.).\n'
          'Do NOT use bullet points or dashes.\n'
          'ONLY provide options that directly relate to the question: "$question"\n'
          'Format your response as a JSON list where each item has "option" and "summary" keys.\n'
          'The "option" key should contain the FULL option text. If the option contains a question and answer, like a joke, the option should contain both the question and the answer.\n'
          '$summaryInstruction\n'
          'Example: [{"option": "I want to go outside", "summary": "Go outside"}, {"option": "Can I have some water please?", "summary": "Water please"}]';"""

# Use a simpler string replacement
old_text = """final promptForLLM =
          'Provide up to "${llmOptions}" short, single-phrase options related to: "${question}".\\n'
          'Do not include any introductory or concluding text.\\n'
          'Do NOT number your responses (no 1., 2., 3., etc.).\\n'
          'Do NOT use bullet points or dashes.\\n'
          'Format your response as a JSON list where each item has "option" and "summary" keys.\\n'
          'The "option" key should contain the FULL option text. If the option contains a question and answer, like a joke, the option contain the question and the answer.\\n'
          '[0m${summaryInstruction}\\n'
          'Example: [{"option": "...", "summary": "..."}]';"""

new_text = """final promptForLLM =
          'Generate exactly $llmOptions short, single-phrase options that directly answer or respond to: "$question".\\n'
          'IMPORTANT: Provide exactly $llmOptions options, no more, no less. Each option must be relevant to the question asked.\\n'
          'Do NOT include any introductory text, concluding text, explanations, or unrelated information.\\n'
          'Do NOT number your responses (no 1., 2., 3., etc.).\\n'
          'Do NOT use bullet points or dashes.\\n'
          'ONLY provide options that directly relate to the question: "$question"\\n'
          'Format your response as a JSON list where each item has "option" and "summary" keys.\\n'
          'The "option" key should contain the FULL option text. If the option contains a question and answer, like a joke, the option should contain both the question and the answer.\\n'
          '$summaryInstruction\\n'
          'Example: [{"option": "I want to go outside", "summary": "Go outside"}, {"option": "Can I have some water please?", "summary": "Water please"}]';"""

if old_text in content:
    content = content.replace(old_text, new_text)
    print("✅ Successfully updated the wake word LLM prompt")
    
    # Write back
    with open('lib/main.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("✅ File updated successfully")
else:
    print("❌ Could not find the old prompt text")
    print("Searching for partial match...")
    if 'Provide up to' in content and 'llmOptions' in content:
        print("Found 'Provide up to' - the prompt is in the file but format may differ")
    else:
        print("Prompt text not found at all")
