#!/usr/bin/env python3
"""Update wake word prompt in main.dart to match gridpage.js exactly"""

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# The old prompt as it currently exists
old_prompt = '''      final promptForLLM =
          'Provide up to $llmOptions short, single-phrase options related to: "$question".\\n'
          'Each option should help answer or respond to: "$question"\\n'
          'Do not include jokes or humor unless the question specifically asks for them.\\n'
          'Do not include any introductory or concluding text.\\n'
          'Do NOT number your responses (no 1., 2., 3., etc.).\\n'
          'Do NOT use bullet points or dashes.\\n'
          'Format your response as a JSON list where each item has "option" and "summary" keys.\\n'
          'The "option" key should contain the FULL option text. If the option contains a question and answer, like a joke, the option contain the question and the answer.\\n'
          '$summaryInstruction\\n'
          'Example: [{"option": "I want to go outside", "summary": "Go outside"}, {"option": "Can I have some water please?", "summary": "Water please"}]';'''

# The new prompt matching gridpage.js
new_prompt = '''      final promptForLLM =
          'Provide up to "$llmOptions" short, single-phrase options related to: "$question".\\n'
          'Do not include any introductory or concluding text.\\n'
          'Format your response as a JSON list where each item has "option", "summary", and "keywords" keys.\\n'
          'The "option" key should contain the FULL option text. If the option contains a question and answer, like a joke, the option contain the question and the answer.\\n'
          '$summaryInstruction\\n'
          'The "keywords" key should contain 3-5 words that match available symbols. Use these available descriptive words: good, great, happy, sad, angry, excited, tired, hungry, thirsty, hot, cold, big, small, fast, slow, easy, hard, fun, work, play, eat, drink, sleep, walk, run, read, write, look, listen, talk, help, love, like, want, need, more, less, yes, no, stop, go, come, here, there, up, down, in, out, on, off, open, close, new, old, clean, dirty, quiet, loud, light, dark. Focus on concrete, simple words rather than complex descriptives.\\n'
          'Example: [{"option": "What a fantastic day!", "summary": "Fantastic day", "keywords": ["good", "happy", "great", "day", "fun"]}]';'''

if old_prompt in content:
    content = content.replace(old_prompt, new_prompt)
    with open('lib/main.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print("✅ Successfully updated Flutter wake word prompt to match web app gridpage.js")
    print("\nKey changes:")
    print("1. Added quotes around $llmOptions variable")
    print("2. Removed extra constraint lines that web app doesn't have")
    print("3. Added 'keywords' key to JSON format")
    print("4. Added keyword vocabulary list")
    print("5. Updated example to match web app")
else:
    print("❌ Could not find old prompt - it may have already been updated")
    print("\nLooking for prompt starting with:")
    print("  'Provide up to $llmOptions short, single-phrase...'")
