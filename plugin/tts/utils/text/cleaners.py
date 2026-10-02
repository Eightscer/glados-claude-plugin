import os
import re
from typing import Dict, Any

from unidecode import unidecode

from utils.text.numbers import normalize_numbers
from utils.text.symbols import phonemes_set

from dp.phonemizer import Phonemizer

# Regular expression matching whitespace:
_whitespace_re = re.compile(r'\s+')

# Symbol/character expansions for characters the phonemizer can't handle
_symbol_expansions = [
    ('+', ' plus '),
    ('=', ' equals '),
    ('&', ' and '),
    ('@', ' at '),
    ('#', ' hash '),
    ('%', ' percent '),
    ('*', ' star '),
    ('/', ' '),  # path separators: speak the parts, not the slashes
    ('\\', ' backslash '),
    ('~', ' tilde '),
    ('^', ' caret '),
    ('|', ' '),
    ('<', ' less than '),
    ('>', ' greater than '),
    ('_', ' '),  # snake_case: speak the words, not the underscores
]

# Custom pronunciation overrides (word -> phonetic spelling for the phonemizer)
# Applied case-insensitively before phonemization
_custom_pronunciations = [
    (re.compile(r'\bGLaDOS\b', re.IGNORECASE), 'glados'),
    (re.compile(r'\bAperture\b', re.IGNORECASE), 'aperture'),
]

# Pre-phonemized overrides: replace these words AFTER phonemization with exact IPA
# Format: (regex matching the phonemizer output or original word, exact IPA)
_ipa_overrides = {
    'glados': 'ɡlædoʊz',
}

# List of (regular expression, replacement) pairs for abbreviations:
_abbreviations = [(re.compile('\\b%s\\.' % x[0], re.IGNORECASE), x[1]) for x in [
    ('mrs', 'misess'),
    ('mr', 'mister'),
    ('dr', 'doctor'),
    ('st', 'saint'),
    ('co', 'company'),
    ('jr', 'junior'),
    ('maj', 'major'),
    ('gen', 'general'),
    ('drs', 'doctors'),
    ('rev', 'reverend'),
    ('lt', 'lieutenant'),
    ('hon', 'honorable'),
    ('sgt', 'sergeant'),
    ('capt', 'captain'),
    ('esq', 'esquire'),
    ('ltd', 'limited'),
    ('col', 'colonel'),
    ('ft', 'fort')
]]

# Resolve model path relative to the TTS root
_TTS_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_PHONEMIZER_MODEL = os.path.join(_TTS_DIR, 'models', 'en_us_cmudict_ipa_forward.pt')


def expand_symbols(text):
    """Expand symbols like +, -, = to spoken words."""
    for symbol, expansion in _symbol_expansions:
        text = text.replace(symbol, expansion)
    # Context-aware hyphen/minus handling (order matters):
    # Triple+ dashes (---): remove entirely
    text = re.sub(r'-{3,}', ' ', text)
    # Double dash flags: "--force" → "force"
    text = re.sub(r'(?<!\w)--(?=\w)', ' ', text)
    # Single dash flags: "-f" → "dash f"
    text = re.sub(r'(?<!\w)-(?=\w)', 'dash ', text)
    # Math with spaces: "5 - 3", "x - y" → "minus"
    text = re.sub(r'(?<=\w)\s+-\s+(?=\w)', ' minus ', text)
    # Range between digits without spaces: "5-3" → "5 to 3"
    text = re.sub(r'(\d)-(\d)', r'\1 to \2', text)
    # Hyphen joining words: "Decision-Making" → "Decision Making"
    text = re.sub(r'([A-Za-z])-([A-Za-z])', r'\1 \2', text)
    # Cleanup any remaining stray dashes
    text = re.sub(r'\s*-\s*', ' ', text)
    return text


def expand_file_extensions(text):
    """Speak filename dots: "speak.sh" → "speak dot S H", ".gitignore" → "dot gitignore"."""
    # Common Latin abbreviations would otherwise look like extensions
    text = re.sub(r'\be\.g\.', 'for example', text, flags=re.IGNORECASE)
    text = re.sub(r'\bi\.e\.', 'that is', text, flags=re.IGNORECASE)
    # Extension after a name: spell out its letters (capitals phonemize as letter names)
    text = re.sub(r'(?<=\w)\.([A-Za-z][A-Za-z0-9]{0,5})(?!\w)',
                  lambda m: ' dot ' + ' '.join(m.group(1).upper()), text)
    # Dotfile with no name before the dot: keep the word whole
    text = re.sub(r'(?<![\w.])\.([A-Za-z]\w*)', r'dot \1', text)
    return text


def apply_custom_pronunciations(text):
    """Normalize custom words to forms the phonemizer handles correctly."""
    for regex, replacement in _custom_pronunciations:
        text = re.sub(regex, replacement, text)
    return text


def expand_abbreviations(text):
    for regex, replacement in _abbreviations:
        text = re.sub(regex, replacement, text)
    return text


def collapse_whitespace(text):
    return re.sub(_whitespace_re, ' ', text)


def no_cleaners(text):
    return text


def english_cleaners(text):
    text = unidecode(text)
    text = expand_file_extensions(text)
    text = normalize_numbers(text)
    text = expand_abbreviations(text)
    text = expand_symbols(text)
    return text


class Cleaner:

    def __init__(self,
                 cleaner_name: str,
                 use_phonemes: bool,
                 lang: str) -> None:
        if cleaner_name == 'english_cleaners':
            self.clean_func = english_cleaners
        elif cleaner_name == 'no_cleaners':
            self.clean_func = no_cleaners
        else:
            raise ValueError(f'Cleaner not supported: {cleaner_name}! '
                             f'Currently supported: [\'english_cleaners\', \'no_cleaners\']')
        self.use_phonemes = use_phonemes
        self.lang = lang
        if use_phonemes:
            self.phonemize = Phonemizer.from_checkpoint(_PHONEMIZER_MODEL)

    def __call__(self, text: str) -> str:
        text = self.clean_func(text)
        if self.use_phonemes:
            # Split text around words with custom IPA, phonemize segments,
            # and splice in the exact IPA for custom words.
            # Build a combined regex for all custom pronunciation words
            if _ipa_overrides:
                combined_pattern = '|'.join(
                    regex.pattern for regex, _ in _custom_pronunciations
                    if _ in _ipa_overrides
                )
                if combined_pattern:
                    parts = re.split(f'({combined_pattern})', text, flags=re.IGNORECASE)
                    result_parts = []
                    for part in parts:
                        if not part:
                            continue
                        # Check if this part matches a custom word
                        matched_ipa = None
                        for regex, normalized in _custom_pronunciations:
                            if normalized in _ipa_overrides and re.fullmatch(regex.pattern, part, re.IGNORECASE):
                                matched_ipa = _ipa_overrides[normalized]
                                break
                        if matched_ipa:
                            result_parts.append(matched_ipa)
                        else:
                            phonemized = self.phonemize(part, lang='en_us')
                            result_parts.append(phonemized)
                    text = ''.join(result_parts)
                else:
                    text = self.phonemize(text, lang='en_us')
            else:
                text = self.phonemize(text, lang='en_us')

            text = ''.join([p for p in text if p in phonemes_set])
        text = collapse_whitespace(text)
        text = text.strip()
        return text
