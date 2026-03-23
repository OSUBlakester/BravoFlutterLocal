// TAP INTERFACE FOLLOW-UP CONVERSATION LOGIC
// This file contains the conversation tracking and partner-engagement logic
// ported from gridpage.js to work with the Tap Interface

function classifyCommunicationType(text) {
    if (!text || typeof text !== 'string') return 'assertion';
    const normalized = text.trim().toLowerCase();
    if (/^(hello|hi|hey|good morning|good afternoon|good evening|greetings)/i.test(normalized)) return 'greeting';
    if (/^(i want|i need|could you|can you|would you|please|let's|how about)/i.test(normalized)) return 'request';
    if (/\?\s*$/.test(normalized) || /^(what|where|when|who|why|how|do|does|did|is|are|can|could|would|will|should)/i.test(normalized)) return 'question';
    if (/^(yes|no|okay|sure|maybe|perhaps|i think so|i don't think so|probably)/i.test(normalized)) return 'answer';
    if (/(ha|haha|lol|funny|joke)/i.test(normalized)) return 'joke';
    if (/^(exactly|absolutely|totally|definitely|that's right|i agree|me too)/i.test(normalized)) return 'affirmation';
    return 'assertion';
}

function classifyFollowUpGuidance(communicationType) {
    const guidanceMap = {
        greeting: {
            description: "User has greeted someone. Follow-ups should ask about the person's day, invite conversation, or suggest activities.",
            patterns: [
                "How are you doing today?",
                "What are you up to?",
                "Can we chat for a bit?",
                "Are you having a good day?",
                "Do you want to talk?",
                "What's new with you?"
            ]
        },
        assertion: {
            description: "User has made a statement or expressed an opinion/feeling. Follow-ups should expound on the topic OR invite partner engagement with questions.",
            patterns: [
                "What do you think about this?",
                "Do you agree with me?",
                "Have you felt this way too?",
                "Can we talk about this?",
                "What would you do?",
                "Do you want to know more?"
            ]
        },
        question: {
            description: "User has asked a question. Follow-ups should provide related questions or statements to continue the inquiry.",
            patterns: [
                "What do you think about that?",
                "Do you have an idea?",
                "Can we figure this out together?",
                "Would you choose the same?",
                "Should we decide together?",
                "I'm curious what you think."
            ]
        },
        request: {
            description: "User has made a request. Follow-ups should clarify the request or invite the partner to help.",
            patterns: [
                "Can you help me with this?",
                "Would you do this with me?",
                "Do you think this would work?",
                "Should we try this now?",
                "Can we do this together?",
                "What do you think?"
            ]
        },
        answer: {
            description: "User has provided an answer. Follow-ups should check understanding or continue the conversation.",
            patterns: [
                "Does that make sense to you?",
                "What do you think about that?",
                "Do you want to know more?",
                "Should I explain more?",
                "Do you agree with that?",
                "Is that helpful?"
            ]
        },
        joke: {
            description: "User has told a joke or made a humorous comment. Follow-ups should be playful or invite the partner to share.",
            patterns: [
                "Do you think that's funny?",
                "Want to hear another one?",
                "Did that make you laugh?",
                "Do you have a joke too?",
                "Should I tell one more?",
                "That was silly, right?"
            ]
        },
        affirmation: {
            description: "User has agreed or affirmed. Follow-ups should build on the agreement or suggest next steps.",
            patterns: [
                "Do you feel the same way?",
                "Would you agree with that?",
                "What do you think?",
                "Should we do that together?",
                "Do you want to join me?",
                "Can we talk more about this?"
            ]
        }
    };
    return guidanceMap[communicationType] || guidanceMap.assertion;
}

function isPartnerInterrogativePattern(text) {
    if (!text || typeof text !== 'string') return false;
    const normalized = text.trim().toLowerCase();
    const selectedPhrases = Array.isArray(tapFollowUpConversation.selectedPhrases) ? tapFollowUpConversation.selectedPhrases : [];
    const latestPhrase = selectedPhrases.length > 0 ? selectedPhrases[selectedPhrases.length - 1] : '';
    const wasUserAssertion = /^\s*(i\b|i\'m\b|i am\b)/i.test(latestPhrase);
    
    if (wasUserAssertion) {
        if (/^tell me (about|more|what|why|how)/i.test(normalized)) return true;
        if (/^what (is |are |makes |made )?(making|made) you/i.test(normalized)) return true;
        if (/^what makes you/i.test(normalized)) return true;
        if (/^why (are|do) you/i.test(normalized)) return true;
        if (/^how (does|do) (that|this|it) make you feel/i.test(normalized)) return true;
        if (/^describe (how|what|why)/i.test(normalized)) return true;
    }
    
    if (/^(why are you|why do you|how does (that|it|this) make you feel|how are you feel)/i.test(normalized)) return true;
    if (/^what kind of .+ are you/i.test(normalized)) return true;
    if (/^can you tell me/i.test(normalized)) return true;
    
    return false;
}

function isQuestionLikeOption(text) {
    if (!text || typeof text !== 'string') return false;
    const trimmed = text.trim();
    if (!trimmed) return false;
    if (/[?]\s*$/.test(trimmed)) return true;
    return /^(do|does|did|are|is|can|could|would|will|have|has|should|what|which|when|where|why|how|who)\b/i.test(trimmed);
}

function buildPartnerQuestionFallbacksForTap(latestPhrase, neededCount) {
    const communicationType = classifyCommunicationType(latestPhrase || '');
    const templatesByType = {
        assertion: [
            'What do you think about this?',
            'Do you agree with me?',
            'Have you felt this way too?',
            'Can we talk about this?',
            'What would you do in my place?'
        ],
        affirmation: [
            'Do you feel the same way?',
            'Would you agree with that?',
            'What do you think?',
            'Should we do that together?',
            'Do you want to join me?'
        ],
        request: [
            'Can you help me with this?',
            'Would you do this with me?',
            'Do you think this would work?',
            'Should we try this now?',
            'Can we do this together?'
        ],
        answer: [
            'Does that make sense to you?',
            'What do you think about that?',
            'Do you want to know more?',
            'Should I explain more?',
            'Do you agree with that?'
        ],
        joke: [
            'Do you think that is funny?',
            'Want to hear another one?',
            'Did that make you laugh?',
            'Do you have a joke too?',
            'Should I tell one more?'
        ],
        greeting: [
            'How are you doing today?',
            'What are you up to?',
            'Can we chat for a bit?',
            'Are you having a good day?',
            'Do you want to talk?'
        ],
        question: [
            'What do you think about that?',
            'Do you have an idea?',
            'Can we figure this out together?',
            'Would you choose the same?',
            'Should we decide together?'
        ]
    };

    const templates = templatesByType[communicationType] || templatesByType.assertion;
    const selectedTemplates = templates.slice(0, Math.max(0, neededCount));
    return selectedTemplates.map((text) => ({
        option: text,
        summary: text,
        keywords: text.toLowerCase().split(/\s+/).filter(w => w.length > 3).slice(0, 5)
    }));
}

function normalizeForComparisonTap(text) {
    if (!text || typeof text !== 'string') return '';
    return text
        .toLowerCase()
        .replace(/["'""'']/g, '')
        .replace(/[^a-z0-9\s]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

function tokenizeForContextTap(text) {
    if (!text || typeof text !== 'string') return [];
    const stopWords = new Set([
        'the', 'a', 'an', 'and', 'or', 'but', 'if', 'then', 'to', 'of', 'for', 'in', 'on', 'at', 'with', 'from',
        'is', 'are', 'was', 'were', 'be', 'been', 'being', 'it', 'this', 'that', 'i', 'you', 'we', 'they', 'he', 'she',
        'do', 'does', 'did', 'want', 'wants', 'would', 'could', 'should', 'can', 'will', 'today', 'tonight', 'afternoon'
    ]);
    return text
        .toLowerCase()
        .replace(/[^a-z0-9\s]/g, ' ')
        .split(/\s+/)
        .map(token => token.trim())
        .filter(token => token.length > 1 && !stopWords.has(token));
}

function scoreOptionContextualFitTap(optionData, contextTerms, latestPhraseTerms) {
    const optionText = typeof optionData.option === 'string' ? optionData.option : '';
    const summaryText = typeof optionData.summary === 'string' ? optionData.summary : '';
    const keywordText = Array.isArray(optionData.keywords) ? optionData.keywords.join(' ') : '';
    const combinedText = `${optionText} ${summaryText} ${keywordText}`;
    const optionTerms = tokenizeForContextTap(combinedText);
    const optionTermSet = new Set(optionTerms);

    let score = 0;
    for (const term of contextTerms) {
        if (optionTermSet.has(term)) score += 4;
    }
    for (const term of latestPhraseTerms) {
        if (optionTermSet.has(term)) score += 6;
    }

    const wordCount = optionText.trim().split(/\s+/).filter(Boolean).length;
    if (wordCount >= 2 && wordCount <= 10) score += 1;
    if (wordCount > 14) score -= 2;

    if (/^i\s+want\s+to\b/i.test(optionText) || /^let('|')s\b/i.test(optionText) || /^how about\b/i.test(optionText)) {
        score += 1;
    }

    // BOOST: Prioritize partner-engagement questions
    const partnerEngagementPatterns = [/^do you\b/i, /^would you\b/i, /^can you\b/i, /^could you\b/i, /^have you\b/i, /^what do you think\b/i, /^what do you feel\b/i, /^are you\b/i, /^should we\b/i, /^do you want\b/i, /^will you\b/i, /^do you like\b/i, /^what's your\b/i, /^who wants\b/i];
    if (partnerEngagementPatterns.some(pattern => pattern.test(optionText))) score += 8;

    if ((optionText.match(/[.!?]/g) || []).length > 1) {
        score -= 2;
    }

    return score;
}

function prioritizeContextualOptionsTap(options, contextText, maxCount) {
    if (!Array.isArray(options) || options.length === 0) return [];

    const contextTerms = tokenizeForContextTap(contextText || '');
    const latestPhrase = Array.isArray(tapFollowUpConversation.selectedPhrases) && tapFollowUpConversation.selectedPhrases.length > 0
        ? tapFollowUpConversation.selectedPhrases[tapFollowUpConversation.selectedPhrases.length - 1]
        : '';
    const latestPhraseTerms = tokenizeForContextTap(latestPhrase);

    const scored = options.map((optionData, index) => ({
        optionData,
        index,
        score: scoreOptionContextualFitTap(optionData, contextTerms, latestPhraseTerms)
    }));

    scored.sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score;
        return a.index - b.index;
    });

    const selected = scored.slice(0, Math.max(1, maxCount)).map(item => item.optionData);
    console.log('TAP Context prioritization scores:', scored.map(s => ({ idx: s.index, score: s.score, summary: s.optionData?.summary })));
    return selected;
}

function enforceAdditiveFollowUpOptionsTap(options, maxCount) {
    if (!Array.isArray(options) || options.length === 0) return [];

    const selectedPhrases = Array.isArray(tapFollowUpConversation.selectedPhrases)
        ? tapFollowUpConversation.selectedPhrases
        : [];
    const latestPhrase = selectedPhrases.length > 0
        ? selectedPhrases[selectedPhrases.length - 1]
        : '';

    const latestNormalized = normalizeForComparisonTap(latestPhrase);
    if (!latestNormalized) {
        return options.slice(0, Math.max(1, maxCount));
    }

    const additive = [];
    for (const item of options) {
        if (!item || typeof item.option !== 'string') continue;

        const rawOption = item.option.trim();
        if (!rawOption) continue;

        let updatedOption = rawOption;
        const normalizedOption = normalizeForComparisonTap(rawOption);

        if (normalizedOption === latestNormalized) {
            continue;
        }

        if (normalizedOption.startsWith(latestNormalized)) {
            const escapedLatest = latestPhrase.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            const prefixRegex = new RegExp(`^\\s*${escapedLatest}\\s*[!?.:,;\-–—]*\\s*`, 'i');
            updatedOption = updatedOption.replace(prefixRegex, '').trim();

            if (!updatedOption) {
                const firstBreak = rawOption.search(/[!?.]\s+/);
                if (firstBreak >= 0) {
                    updatedOption = rawOption.slice(firstBreak + 1).trim();
                }
            }
        }

        if (!updatedOption) continue;

        const updatedNormalized = normalizeForComparisonTap(updatedOption);
        if (!updatedNormalized || updatedNormalized === latestNormalized) continue;

        additive.push({
            ...item,
            option: updatedOption,
            summary: item.summary && typeof item.summary === 'string' ? item.summary : updatedOption
        });
    }

    return additive.slice(0, Math.max(1, maxCount));
}

function prioritizePartnerEngagementQuestionsTap(options, maxCount, minQuestionCount) {
    if (!Array.isArray(options) || options.length === 0) return [];

    const selectedPhrases = Array.isArray(tapFollowUpConversation.selectedPhrases)
        ? tapFollowUpConversation.selectedPhrases
        : [];
    const latestPhrase = selectedPhrases.length > 0
        ? selectedPhrases[selectedPhrases.length - 1]
        : '';

    const questions = [];
    const nonQuestions = [];

    for (const item of options) {
        const text = typeof item?.option === 'string' ? item.option.trim() : '';
        if (!text) continue;
        if (isQuestionLikeOption(text)) {
            questions.push(item);
        } else {
            nonQuestions.push(item);
        }
    }

    const targetQuestions = Math.min(Math.max(1, minQuestionCount), Math.max(1, maxCount));
    let supplementalQuestions = [];
    if (questions.length < targetQuestions) {
        supplementalQuestions = buildPartnerQuestionFallbacksForTap(latestPhrase, targetQuestions - questions.length);
    }

    const merged = [...questions, ...supplementalQuestions, ...nonQuestions];
    const deduped = [];
    const seen = new Set();
    for (const item of merged) {
        const text = typeof item?.option === 'string' ? item.option.trim() : '';
        const normalized = normalizeForComparisonTap(text);
        if (!normalized || seen.has(normalized)) continue;
        seen.add(normalized);
        deduped.push(item);
    }

    const result = deduped.slice(0, Math.max(1, maxCount));
    const resultQuestionCount = result.filter(item => isQuestionLikeOption(item?.option)).length;
    console.log('TAP ❓ Partner question prioritization:', {
        inputCount: options.length,
        existingQuestionCount: questions.length,
        supplementalQuestionCount: supplementalQuestions.length,
        outputCount: result.length,
        outputQuestionCount: resultQuestionCount,
        targetQuestions
    });
    return result;
}

function getTapConversationContextText() {
    const parts = [];
    
    if (currentQuestion && currentQuestion.trim()) {
        parts.push(`Question asked: "${currentQuestion}"`);
    }
    
    if (currentCategory && currentCategory.label && currentCategory.label !== 'general') {
        parts.push(`Current category: "${currentCategory.label}"`);
    }
    
    if (Array.isArray(tapFollowUpConversation.selectedPhrases) && tapFollowUpConversation.selectedPhrases.length > 0) {
        const phrasesText = tapFollowUpConversation.selectedPhrases.join(' → ');
        parts.push(`User has said: "${phrasesText}"`);
    }
    
    return parts.join('. ');
}

function normalizeTapLlmOptions(rawItems) {
    if (!Array.isArray(rawItems)) return [];

    const normalized = rawItems.map(item => {
        if (!item) return null;

        if (typeof item === 'string') {
            const text = item.trim();
            if (!text) return null;
            return { option: text, summary: text, keywords: [] };
        }

        if (typeof item !== 'object') return null;

        const summary = typeof item.summary === 'string' ? item.summary.trim() : '';
        const directOption = typeof item.option === 'string' ? item.option.trim() : '';

        if (directOption) {
            return {
                option: directOption,
                summary: summary || directOption,
                keywords: Array.isArray(item.keywords) ? item.keywords : []
            };
        }

        const candidateKey = Object.keys(item).find(key => key !== 'summary' && key !== 'keywords');
        const candidateValue = candidateKey ? item[candidateKey] : null;
        const inferredOption = typeof candidateValue === 'string' ? candidateValue.trim() : '';
        if (!inferredOption) return null;

        return {
            option: inferredOption,
            summary: summary || inferredOption,
            keywords: Array.isArray(item.keywords) ? item.keywords : []
        };
    }).filter(Boolean);

    if (normalized.length !== rawItems.length) {
        console.warn(`TAP normalizeTapLlmOptions filtered malformed items: ${rawItems.length - normalized.length}`);
    }

    return normalized;
}

function buildFollowUpPromptForTap(excludedOptionsText = '') {
    const summaryInstruction = SummaryOff
        ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
        : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';

    const conversationContext = getTapConversationContextText();
    const selectedPhrases = Array.isArray(tapFollowUpConversation.selectedPhrases)
        ? tapFollowUpConversation.selectedPhrases
        : [];
    const latestPhrase = selectedPhrases.length > 0
        ? selectedPhrases[selectedPhrases.length - 1]
        : '';
    
    const communicationType = latestPhrase
        ? classifyCommunicationType(latestPhrase)
        : 'assertion';
    const typeGuidance = classifyFollowUpGuidance(communicationType);
    
    const exclusionLine = excludedOptionsText && excludedOptionsText.trim()
        ? `Avoid repeating these existing options: "${excludedOptionsText}".`
        : '';
    const latestFocusLine = latestPhrase
        ? `Latest selected phrase (PRIMARY FOCUS): "${latestPhrase}".`
        : '';
    const noContextLine = !conversationContext
        ? 'No explicit category or question is selected. Continue a natural social conversation from the latest user phrase.'
        : '';
    
    const typePatternExamples = typeGuidance.patterns
        .slice(0, 4)
        .map(pattern => `  • ${pattern}`)
        .join('\n');

    return `
AAC COMMUNICATION SYSTEM - GENERATING USER'S NEXT SPEECH OPTIONS

SCENARIO:
An AAC user is having a conversation using the Tap Interface. They select pre-written phrase options to speak.
The user has ALREADY SPOKEN the following to their communication partner:
${conversationContext}
${noContextLine}
Most recently, the user JUST SAID OUT LOUD: "${latestPhrase}"

YOUR TASK:
Generate ${LLMOptions} MORE things the SAME user can SAY, ASK, BUILD, or EXPOUND next to continue THEIR speaking turn.
These are OPTIONS FOR THE USER TO SELECT AND SPEAK (including statements and partner-engagement questions), not responses TO the user.

🚫🚫🚫 CRITICAL ERROR TO AVOID 🚫🚫🚫

The user JUST SAID: "I am over the moon with excitement!"

DO NOT GENERATE: "Tell me more about what makes you feel this way!"
WHY THIS IS WRONG: The user JUST expressed excitement. They don't ask THEMSELVES to tell them more about their own feeling. That would be the PARTNER asking the user a question.

DO NOT GENERATE: "What's making you so excited?"  
WHY THIS IS WRONG: The user doesn't ask themselves what's making them excited. That's the PARTNER questioning the user.

DO NOT GENERATE: "Tell me...", "What makes you...", "What's making you...", "Describe...", "Explain..."
WHY: These are PARTNER phrases asking the user to elaborate. The user doesn't interview themselves.

✅ CORRECT EXAMPLES - Generate options like these:

The user JUST SAID: "I am over the moon with excitement!"
GENERATE: "This is the best day ever!" ✅ (User expounding on their emotion)
GENERATE: "Do you want to celebrate with me?" ✅ (User inviting partner)
GENERATE: "I can't wait to do something fun!" ✅ (User continuing their expression)
GENERATE: "Are you excited too?" ✅ (User engaging partner)
GENERATE: "Something amazing just happened!" ✅ (User adding context)

COMMUNICATION TYPE: ${communicationType.toUpperCase()}
${typeGuidance.description}

PATTERN EXAMPLES FOR ${communicationType.toUpperCase()}:
${typePatternExamples}

RULES FOR GENERATION:
1. The user is SPEAKING, not being interviewed
2. The user is continuing THEIR turn (partner hasn't responded yet)
3. Generate things the user would SAY or ASK to engage the partner, not questions someone would ASK the user
4. Options should BUILD/EXPOUND on their point OR invite partner engagement
5. Keep options short, conversational, and natural
6. NO "Tell me", "What makes you", "Describe", "Explain" after user assertions
7. Include at least 4 partner-engagement QUESTIONS that end with "?" and invite the partner to respond

${latestFocusLine}
${exclusionLine}
Return ONLY a JSON list where each item has "option", "summary", and "keywords" keys.
The "option" key should contain the FULL option text.
${summaryInstruction}
The "keywords" key should contain 3-5 words that match available symbols. Use these available descriptive words: good, great, happy, sad, angry, excited, tired, hungry, thirsty, hot, cold, big, small, fast, slow, easy, hard, fun, work, play, eat, drink, sleep, walk, run, read, write, look, listen, talk, help, love, like, want, need, more, less, yes, no, stop, go, come, here, there, up, down, in, out, on, off, open, close, new, old, clean, dirty, quiet, loud, light, dark. Focus on concrete, simple words rather than complex descriptives.
`;
}
