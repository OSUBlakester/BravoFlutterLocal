"""
Accent MTI File Parser for Bravo Migration Tool

Parses Accent .mti files (binary format) and extracts page/button data.
MTI files contain compressed button configurations with:
- Page IDs and button positions
- Button labels, icons, speech text
- Navigation targets and functions

Based on extract_mti_to_json.py implementation.
"""

import struct
import zlib
from typing import Dict, List, Optional
import logging

logger = logging.getLogger(__name__)


class AccentMTIParser:
    """Parser for Accent MTI configuration files."""
    
    # MTI file uses 7 rows x 16 columns grid
    ACCENT_GRID_COLS = 16
    
    def __init__(self):
        self.pages = {}
        self.metadata_pages = {}
        self.page_names = {}
        self.format_stats = {
            'Format 1 - Standard': 0,
            'Format 2 - Null-terminated': 0,
            'Format 3 - Offset name': 0,
            'Format 4 - Simple speech': 0,
            'Format 5 - Function-based': 0,
            'Complex format': 0
        }
        
    def parse_file(self, file_path: str) -> Dict:
        """
        Parse an MTI file and extract all pages and buttons.
        
        Args:
            file_path: Path to the .mti file
            
        Returns:
            Dict with structure:
            {
                'pages': {page_id: {page_data}},
                'total_pages': int,
                'total_buttons': int
            }
        """
        try:
            # Read and decompress the MTI file
            # MTI files have format: v500 header line, 4 mystery bytes, CRLF, then zlib compressed data
            with open(file_path, 'rb') as f:
                # Skip the header
                f.readline()  # Skip "v500 1 NUVOICE\r\n" line
                f.read(4)     # Skip 4 mystery bytes
                f.read(2)     # Skip CRLF
                
                # Rest is zlib compressed data
                compressed_data = f.read()
            
            logger.info(f"Compressed data size: {len(compressed_data)} bytes")
            
            # Decompress
            decompressed = zlib.decompress(compressed_data)
            logger.info(f"Decompressed {len(decompressed)} bytes")
            
            # Extract pages and buttons
            self._extract_pages(decompressed)
            
            # Apply page naming from metadata
            self._apply_page_names()
            
            # Process navigation targets
            self._process_navigation()
            
            # Separate metadata pages (40XX range)
            real_pages = {pid: pdata for pid, pdata in self.pages.items() 
                         if not pid.startswith('4')}
            self.metadata_pages = {pid: pdata for pid, pdata in self.pages.items() 
                                  if pid.startswith('4')}
            
            total_buttons = sum(p['button_count'] for p in real_pages.values())
            
            logger.info(f"Extracted {total_buttons} buttons from {len(real_pages)} pages")
            logger.info(f"Format breakdown: {self.format_stats}")
            
            return {
                'pages': real_pages,
                'total_pages': len(real_pages),
                'total_buttons': total_buttons,
                'metadata_pages': self.metadata_pages,
                'format_stats': self.format_stats
            }
            
        except Exception as e:
            logger.error(f"Error parsing MTI file: {e}")
            raise
    
    def _extract_pages(self, data: bytes):
        """Extract all pages and buttons from decompressed MTI data."""
        # Look for m-records (button definitions)
        # Format: m\x00\x04\xfd followed by button data
        
        pos = 0
        button_count = 0
        
        while pos < len(data) - 20:
            # Find m-record marker
            if data[pos:pos+4] != b'm\x00\x04\xfd':
                pos += 1
                continue
            
            try:
                # Extract page ID (2 bytes after marker) and SWAP BYTES
                # MTI stores as 0x0004 but we display as 0x0400
                page_id_bytes = data[pos+4:pos+6]
                page_id_raw = struct.unpack('<H', page_id_bytes)[0]
                
                # Byte-swap the page ID: swap high and low bytes
                page_id_swapped = ((page_id_raw & 0xFF) << 8) | ((page_id_raw >> 8) & 0xFF)
                page_id_str = f"{page_id_swapped:04x}"
                
                # Extract sequence (button position, 1 byte)
                sequence = data[pos+6]
                
                # Calculate grid position
                row = sequence // self.ACCENT_GRID_COLS
                col = sequence % self.ACCENT_GRID_COLS
                
                # Parse button based on format
                button = self._parse_button(data, pos, page_id_str, sequence, row, col)
                
                if button:
                    # Add to pages dict
                    if page_id_str not in self.pages:
                        self.pages[page_id_str] = {
                            'page_id': page_id_str,
                            'inferred_name': f'Page_{page_id_str}',
                            'button_count': 0,
                            'buttons': []
                        }
                    
                    self.pages[page_id_str]['buttons'].append(button)
                    self.pages[page_id_str]['button_count'] += 1
                    button_count += 1
                    
                    # Store 40XX metadata for page naming
                    if page_id_str.startswith('40') and button['name']:
                        self.page_names[(page_id_str, sequence)] = button['name']
                
                # Move past the marker to continue searching
                pos += 4
                
            except Exception as e:
                pos += 1
                continue
        
        logger.info(f"Extracted {button_count} buttons from {len(self.pages)} pages")
    
    def _parse_button(self, data: bytes, pos: int, page_id: str, 
                     sequence: int, row: int, col: int) -> Optional[Dict]:
        """
        Parse a single button record - EXACT logic from extract_mti_to_json.py
        
        MTI format has 5 button formats:
        - Format 5: Function-based (0xCC or 0xFF markers)
        - Format 2: Null-terminated (byte_9 == 0)
        - Format 1: Standard (byte_9 1-49)
        - Format 4: Simple speech (byte_9 50-100)
        - Format 3: Offset name (byte_9 > 100)
        """
        button_name = ""
        icon_name = None
        speech = None
        navigation_type = None
        navigation_target = None
        functions = []
        has_goto_home = False  # Track if GOTO-HOME is present
        
        try:
            byte_9 = data[pos+9]
            
            # Format 5: Function-based (0x87, 0xAF, 0xCC or 0xFF markers)
            # These have variable-length data, parse carefully
            if byte_9 in [0x87, 0xaf, 0xcc, 0xff] and pos + 14 < len(data):
                # Format 5: All function-based records (0x87, 0xAF, 0xCC, 0xFF)
                # Name length is at byte 13
                name_len = data[pos+13]
                if 0 < name_len < 100:
                    button_name = data[pos+14:pos+14+name_len].decode('ascii', errors='ignore')
                    pos_cursor = pos + 14 + name_len
                    
                    # Skip null terminator if present
                    if pos_cursor < len(data) and data[pos_cursor] == 0:
                        pos_cursor += 1
                    
                    # Find the end of this button (CRLF terminator) to limit search window
                    button_end = data.find(b'\r\n', pos_cursor)
                    if button_end == -1:
                        button_end = min(pos_cursor + 50, len(data))
                    else:
                        button_end = min(button_end, pos_cursor + 50)
                    
                    search_region = data[pos_cursor:button_end]
                    go_back_page_pos = search_region.find(b'\xff\x81\x05\xfe')
                    
                    # Check for FF 80 navigation patterns (SET-PAGE, CLEAR-DISPLAY, GOTO-HOME)
                    clear_display_pos = search_region.find(b'\xff\x80\x3a\xfe')
                    set_page_perm_pos = search_region.find(b'\xff\x80\x8c')
                    set_page_temp_pos = search_region.find(b'\xff\x80\x8d')
                    goto_home_pos = search_region.find(b'\xff\x80\x85\xfe')
                    
                    if go_back_page_pos != -1:
                        # GO-BACK-PAGE function detected
                        navigation_type = 'GO-BACK-PAGE'
                        navigation_target = None
                        functions.append('GO-BACK-PAGE')
                        speech = None  # Navigation buttons have no speech
                        logger.info(f"GO-BACK-PAGE detected on page {page_id}, button {button_name}")
                        # Skip the rest of Format 5 processing
                    elif goto_home_pos != -1:
                        # GOTO-HOME function detected (FF 80 85 FE pattern)
                        navigation_type = 'PERMANENT'
                        navigation_target = '0400'  # Home page
                        functions.append('GOTO-HOME')
                        has_goto_home = True
                        speech = None  # Navigation buttons have no speech
                        logger.info(f"GOTO-HOME (FF 80 85 FE) detected on page {page_id}, button {button_name}")
                    elif clear_display_pos != -1 or set_page_perm_pos != -1 or set_page_temp_pos != -1:
                        # FF 80 navigation pattern detected - handle like Format 3
                        # Process CLEAR-DISPLAY
                        if clear_display_pos != -1:
                            functions.append('CLEAR-DISPLAY')
                        
                        # Process SET-PAGE (PERMANENT or TEMPORARY)
                        if set_page_perm_pos != -1:
                            # Extract target page name between FF 80 8C and FE
                            target_start = set_page_perm_pos + 3
                            target_end = search_region.find(b'\xfe', target_start)
                            if target_end != -1:
                                target_name = search_region[target_start:target_end].decode('ascii', errors='ignore')
                                navigation_type = 'PERMANENT'
                                navigation_target = target_name
                                functions.append(f'SET-PAGE({target_name})')
                        elif set_page_temp_pos != -1:
                            # Extract target page name between FF 80 8D and FE
                            target_start = set_page_temp_pos + 3
                            target_end = search_region.find(b'\xfe', target_start)
                            if target_end != -1:
                                target_name = search_region[target_start:target_end].decode('ascii', errors='ignore')
                                navigation_type = 'TEMPORARY'
                                navigation_target = target_name
                                functions.append(f'SET-PAGE({target_name})')
                        
                        # Extract speech if present (between CLEAR-DISPLAY and SET-PAGE or vice versa)
                        if clear_display_pos != -1 and (set_page_perm_pos != -1 or set_page_temp_pos != -1):
                            set_page_pos = set_page_perm_pos if set_page_perm_pos != -1 else set_page_temp_pos
                            if clear_display_pos < set_page_pos:
                                # Speech is between CLEAR-DISPLAY and SET-PAGE
                                speech_start = clear_display_pos + 4
                                speech_bytes = search_region[speech_start:set_page_pos]
                                speech_bytes = speech_bytes.replace(b'\x00', b'').strip()
                                if speech_bytes:
                                    speech = speech_bytes.decode('ascii', errors='ignore').strip()
                            else:
                                # SET-PAGE comes before CLEAR-DISPLAY, no speech
                                speech = None
                        else:
                            # Only one pattern present, no inline speech
                            speech = None
                    else:
                        # Normal Format 5 processing (icon + function markers)
                        # Reset pos_cursor to after name for icon extraction
                        pos_cursor = pos + 14 + name_len
                        
                        # Extract icon
                        if pos_cursor < len(data):
                            icon_len = data[pos_cursor]
                            pos_cursor += 1
                            if 0 < icon_len < 50:
                                icon_name = data[pos_cursor:pos_cursor+icon_len].decode('ascii', errors='ignore')
                                pos_cursor += icon_len
                    
                        # Process function markers (0xA4)
                        while pos_cursor < len(data) - 10 and data[pos_cursor] == 0xa4:
                            func_type = data[pos_cursor+1]
                            pos_cursor += 2
                            
                            if func_type == 0x3a:  # Speech
                                # Find end of speech (next 0xA4 or CRLF)
                                speech_end = pos_cursor
                                while speech_end < len(data) - 2:
                                    if data[speech_end] == 0xa4 or data[speech_end:speech_end+2] == b'\r\n':
                                        break
                                    speech_end += 1
                                speech_bytes = data[pos_cursor:speech_end]
                                # Remove null bytes
                                speech_bytes = speech_bytes.replace(b'\x00', b'')
                                # Decode and strip whitespace FIRST
                                speech = speech_bytes.decode('ascii', errors='ignore').strip()
                                # Then remove trailing garbage characters from the STRING
                                while speech and speech[-1] in ['$', '/', '|', '#', '>', '<', '_', '+', 'F', 'N', 'e', '0']:
                                    speech = speech[:-1].strip()  # Strip again after removing char
                                pos_cursor = speech_end
                                
                            elif func_type == 0x06:  # RANDOM-CHOICE
                                # Extract page reference (in parentheses)
                                ref_start = pos_cursor
                                while ref_start < len(data) and data[ref_start] != 0x28:  # '('
                                    ref_start += 1
                                ref_end = ref_start + 1
                                while ref_end < len(data) and data[ref_end] != 0x29:  # ')'
                                    ref_end += 1
                                if ref_start < ref_end:
                                    ref_page = data[ref_start+1:ref_end].decode('ascii', errors='ignore')
                                    functions.append(f'RANDOM-CHOICE({ref_page})')
                                pos_cursor = ref_end + 1
                                
                            elif func_type == 0x85:  # GO-BACK-PAGE
                                # This function returns to the previous page
                                navigation_type = 'GO-BACK-PAGE'
                                navigation_target = None
                                functions.append('GO-BACK-PAGE')
                                # Skip any trailing data (CRLF usually follows)
                                
                            elif func_type == 0x8b:  # GOTO-HOME
                                # GOTO-HOME always navigates to home page (0400)
                                navigation_target = '0400'  # Home page ID
                                navigation_type = 'PERMANENT'
                                functions.append('GOTO-HOME')
                                has_goto_home = True  # Mark that we've seen GOTO-HOME
                                speech = None  # GOTO-HOME buttons have no speech
                                logger.info(f"GOTO-HOME (0xA4 0x8B) detected on page {page_id}, button {button_name}")
                                
                                # Try to extract target in parentheses (if present)
                                target_start = pos_cursor
                                while target_start < len(data) and target_start < pos_cursor + 20 and data[target_start] != 0x28:
                                    target_start += 1
                                if target_start < len(data) and data[target_start] == 0x28:
                                    target_end = target_start + 1
                                    while target_end < len(data) and target_end < target_start + 20 and data[target_end] != 0x29:
                                        target_end += 1
                                    if target_end < len(data) and data[target_end] == 0x29:
                                        pos_cursor = target_end + 1
                                    else:
                                        pos_cursor = target_start + 1
                                # If no parentheses found, just move past the function marker
                                # The function is already added above
                                
                            elif func_type in [0x8c, 0x8d]:  # Navigation
                                # Only set navigation if we haven't seen GOTO-HOME
                                if not has_goto_home:
                                    nav_type = 'PERMANENT' if func_type == 0x8c else 'TEMPORARY'
                                    # Extract target (in parentheses)
                                    target_start = pos_cursor
                                    while target_start < len(data) and data[target_start] != 0x28:
                                        target_start += 1
                                    target_end = target_start + 1
                                    while target_end < len(data) and data[target_end] != 0x29:
                                        target_end += 1
                                    if target_start < target_end:
                                        navigation_target = data[target_start+1:target_end].decode('ascii', errors='ignore')
                                        navigation_type = nav_type
                                    pos_cursor = target_end + 1
                                else:
                                    # Skip past the navigation marker but don't process it
                                    target_start = pos_cursor
                                    while target_start < len(data) and data[target_start] != 0x28:
                                        target_start += 1
                                    target_end = target_start + 1
                                    while target_end < len(data) and data[target_end] != 0x29:
                                        target_end += 1
                                    pos_cursor = target_end + 1
                        
                        # If no speech was found via markers, fallback to button name
                        if not speech and button_name and not has_goto_home:
                            speech = button_name
                    
                    self.format_stats['Format 5 - Function-based'] += 1
                else:
                    # Invalid name length, skip
                    self.format_stats['Complex format'] += 1
                    return None
                    
            # Format 2: Null-terminated (name_len = 0)
            elif byte_9 == 0:
                # Skip null padding
                pos_cursor = pos + 10
                while pos_cursor < len(data) and data[pos_cursor] == 0:
                    pos_cursor += 1
                
                # Read full text until CRLF
                text_start = pos_cursor
                while pos_cursor < len(data) - 2:
                    if data[pos_cursor:pos_cursor+2] == b'\r\n':
                        break
                    pos_cursor += 1
                
                # Decode the text
                full_text = data[text_start:pos_cursor].decode('ascii', errors='ignore')
                # Remove trailing control characters
                while full_text and ord(full_text[-1]) < 32:
                    full_text = full_text[:-1]
                # Strip whitespace
                full_text = full_text.strip()
                # Remove trailing garbage characters (special markers in MTI format)
                while full_text and full_text[-1] in ['$', '/', '|', '#', '>', '<', '_', '+', 'F', 'N', 'e', '0', 'm']:
                    full_text = full_text[:-1].strip()  # Strip again after removing char
                
                button_name = full_text
                speech = full_text  # Button speaks its own name
                
                self.format_stats['Format 2 - Null-terminated'] += 1
                
            # Format 1: Standard (byte_9 1-49)
            elif 1 <= byte_9 <= 49:
                name_len = byte_9
                button_name = data[pos+10:pos+10+name_len].decode('ascii', errors='ignore')
                pos_cursor = pos + 10 + name_len
                
                # Skip 0x00 separator
                if pos_cursor < len(data) and data[pos_cursor] == 0:
                    pos_cursor += 1
                
                # Check if icon exists: if next byte is 0 or printable ASCII (>= 32), no icon
                if pos_cursor < len(data):
                    potential_icon_len = data[pos_cursor]
                    if 1 <= potential_icon_len <= 30:
                        # This is an icon length byte
                        icon_len = potential_icon_len
                        pos_cursor += 1
                        if pos_cursor + icon_len < len(data):
                            icon_name = data[pos_cursor:pos_cursor+icon_len].decode('ascii', errors='ignore')
                            pos_cursor += icon_len
                
                # Check for 0xA4 function markers (same as Format 5)
                marker_start = pos_cursor
                while pos_cursor < len(data) - 10 and data[pos_cursor] == 0xa4:
                    func_type = data[pos_cursor+1]
                    pos_cursor += 2
                    
                    if func_type == 0x3a:  # Speech marker
                        # Find end of speech (next 0xA4 or 0xA0 or CRLF)
                        speech_end = pos_cursor
                        while speech_end < len(data) - 2:
                            if data[speech_end] == 0xa4 or data[speech_end] == 0xa0 or data[speech_end:speech_end+2] == b'\r\n':
                                break
                            speech_end += 1
                        speech_bytes = data[pos_cursor:speech_end]
                        # Remove null bytes
                        speech_bytes = speech_bytes.replace(b'\x00', b'')
                        # Decode and strip whitespace FIRST
                        speech_text = speech_bytes.decode('ascii', errors='ignore').strip()
                        # Then remove trailing garbage characters from the STRING
                        while speech_text and speech_text[-1] in ['$', '/', '|', '#', '>', '<', '_', '+', 'F', 'N', 'e', '0']:
                            speech_text = speech_text[:-1].strip()  # Strip again after removing char
                        # Only set speech if there's actual text
                        if speech_text:
                            speech = speech_text
                        pos_cursor = speech_end
                    
                    elif func_type == 0x06:  # RANDOM-CHOICE
                        # Extract page reference (in parentheses)
                        ref_start = pos_cursor
                        while ref_start < len(data) and data[ref_start] != 0x28:  # '('
                            ref_start += 1
                        ref_end = ref_start + 1
                        while ref_end < len(data) and data[ref_end] != 0x29:  # ')'
                            ref_end += 1
                        if ref_start < ref_end:
                            ref_page = data[ref_start+1:ref_end].decode('ascii', errors='ignore')
                            functions.append(f'RANDOM-CHOICE({ref_page})')
                        pos_cursor = ref_end + 1
                    
                    elif func_type in [0x8c, 0x8d]:  # SET-PAGE
                        nav_type = 'PERMANENT' if func_type == 0x8c else 'TEMPORARY'
                        # Extract target (in parentheses)
                        target_start = pos_cursor
                        while target_start < len(data) and data[target_start] != 0x28:
                            target_start += 1
                        target_end = target_start + 1
                        while target_end < len(data) and data[target_end] != 0x29:
                            target_end += 1
                        if target_start < target_end:
                            navigation_target = data[target_start+1:target_end].decode('ascii', errors='ignore')
                            navigation_type = nav_type
                            functions.append(f'SET-PAGE({navigation_target})')
                        pos_cursor = target_end + 1
                
                # Check for CLEAR-DISPLAY marker (0xA0) after all 0xA4 markers
                if pos_cursor < len(data) and data[pos_cursor] == 0xa0:
                    functions.append('CLEAR-DISPLAY')
                    pos_cursor += 1
                
                # If we processed function markers, skip the old speech extraction
                if pos_cursor > marker_start:
                    # We processed some function markers, don't extract raw speech
                    if not speech:
                        speech = None
                else:
                    # No function markers, do normal speech extraction
                    # Extract speech - direct ASCII text until CRLF (0x0d 0x0a)
                    if pos_cursor < len(data):
                        speech_start = pos_cursor
                        while pos_cursor < len(data) - 2:
                            if data[pos_cursor:pos_cursor+2] == b'\r\n':
                                break
                            pos_cursor += 1
                        
                        speech_bytes = data[speech_start:pos_cursor]
                        # Remove trailing control characters before CRLF
                        while speech_bytes and speech_bytes[-1] < 32:
                            speech_bytes = speech_bytes[:-1]
                        
                        speech = speech_bytes.decode('ascii', errors='ignore').strip()
                
                if not speech:
                    speech = button_name
                
                self.format_stats['Format 1 - Standard'] += 1
                
            # Format 4: Simple speech (name_len 50-100)
            elif 50 <= byte_9 <= 100:
                name_len = byte_9
                button_name = data[pos+10:pos+10+name_len].decode('ascii', errors='ignore')
                pos_cursor = pos + 10 + name_len
                
                # Skip 0x00 separator
                if pos_cursor < len(data) and data[pos_cursor] == 0:
                    pos_cursor += 1
                
                # Read speech directly (ASCII until CRLF)
                speech_start = pos_cursor
                while pos_cursor < len(data) - 2:
                    if data[pos_cursor:pos_cursor+2] == b'\r\n':
                        break
                    pos_cursor += 1
                
                speech = data[speech_start:pos_cursor].decode('ascii', errors='ignore').strip()
                
                if not speech:
                    speech = button_name
                
                self.format_stats['Format 4 - Simple speech'] += 1
                
            # Format 3: Offset name (name_len > 100)
            elif byte_9 > 100:
                # Real name length is at byte 13
                name_len = data[pos+13]
                button_name = data[pos+14:pos+14+name_len].decode('ascii', errors='ignore')
                
                pos_cursor = pos + 14 + name_len
                
                # Extract icon
                if pos_cursor < len(data):
                    icon_len = data[pos_cursor]
                    pos_cursor += 1
                    if 0 < icon_len < 50:
                        icon_name = data[pos_cursor:pos_cursor+icon_len].decode('ascii', errors='ignore')
                        pos_cursor += icon_len
                
                # Extract speech (2-byte length)
                if pos_cursor + 2 < len(data):
                    speech_len = struct.unpack('<H', data[pos_cursor:pos_cursor+2])[0]
                    pos_cursor += 2
                    if 0 < speech_len < 500:
                        speech = data[pos_cursor:pos_cursor+speech_len].decode('ascii', errors='ignore')
                        pos_cursor += speech_len
                
                # Extract navigation
                if pos_cursor < len(data):
                    nav_byte = data[pos_cursor]
                    if nav_byte in [0x8c, 0x8d]:
                        navigation_type = 'PERMANENT' if nav_byte == 0x8c else 'TEMPORARY'
                        pos_cursor += 1
                        # Find null terminator for target
                        target_start = pos_cursor
                        while pos_cursor < len(data) and data[pos_cursor] != 0:
                            pos_cursor += 1
                        navigation_target = data[target_start:pos_cursor].decode('ascii', errors='ignore')
                
                if not speech:
                    speech = button_name
                
                self.format_stats['Format 3 - Offset name'] += 1
                
            else:
                self.format_stats['Complex format'] += 1
                return None
            
            button_data = {
                'page_id': page_id,
                'sequence': sequence,
                'row': row,
                'col': col,
                'name': button_name,
                'icon': icon_name,
                'speech': speech,
                'functions': functions if functions else None,
                'navigation_type': navigation_type,
                'navigation_target': navigation_target
            }
            
            # Debug logging for GOTO-HOME buttons and beginning button
            if button_name == "beginning" or (functions and 'GOTO-HOME' in functions):
                logger.info(f"BUTTON PARSE: name={button_name}, speech={speech}, functions={functions}, has_goto_home={has_goto_home}, nav_type={navigation_type}, nav_target={navigation_target}")
            
            return button_data
            
        except Exception as e:
            logger.debug(f"Error parsing button at pos {pos}: {e}")
            return None
    
    def _apply_page_names(self):
        """Apply page names from 40XX metadata."""
        # Pattern: Page 40XX, sequence S → defines name for page XXSS
        logger.info("Applying page names from metadata...")
        for (meta_page_id, seq), name in self.page_names.items():
            # Extract XX from 40XX
            target_prefix = meta_page_id[2:]  # Get last 2 chars
            # Format sequence as 2-digit hex
            target_suffix = f"{seq:02x}"
            target_page_id = target_prefix + target_suffix
            
            if target_page_id in self.pages:
                self.pages[target_page_id]['inferred_name'] = name
                logger.debug(f"Page {target_page_id} → '{name}'")
    
    def _process_navigation(self):
        """Process navigation targets and SET-PAGE functions."""
        logger.info("Processing navigation targets...")
        
        # Build page name to ID map
        page_name_to_id = {page_data['inferred_name'].lower().strip(): page_id 
                          for page_id, page_data in self.pages.items()}
        
        for page_id, page_data in self.pages.items():
            for btn in page_data['buttons']:
                # Extract SET-PAGE from speech markers
                if btn['speech'] and '\ufffd' in btn['speech']:
                    parts = btn['speech'].split('\ufffd')
                    for part in parts:
                        part_clean = part.strip().lower()
                        if part_clean in page_name_to_id:
                            btn['navigation_type'] = 'PERMANENT'
                            btn['navigation_target'] = page_name_to_id[part_clean]
                            # Clear speech for navigation-only buttons
                            if not btn['speech'].split('\ufffd')[0].strip() or \
                               btn['speech'].split('\ufffd')[0].strip().endswith(('.', '?')):
                                btn['speech'] = None
                            break
                
                # Check implicit SET-PAGE (speech == name and name matches page)
                if (btn['speech'] and btn['name'] and 
                    btn['speech'].strip().lower() == btn['name'].strip().lower() and
                    not btn['navigation_type']):
                    
                    name_lower = btn['name'].strip().lower()
                    
                    # Try direct match
                    if name_lower in page_name_to_id:
                        btn['navigation_type'] = 'PERMANENT'
                        btn['navigation_target'] = page_name_to_id[name_lower]
                        btn['speech'] = None
                    # Try with "0 " prefix
                    elif f"0 {name_lower}" in page_name_to_id:
                        btn['navigation_type'] = 'PERMANENT'
                        btn['navigation_target'] = page_name_to_id[f"0 {name_lower}"]
                        btn['speech'] = None
                
                # Extract navigation from speech patterns
                # Skip if button has GOTO-HOME function (navigation already set to 'home')
                if btn['speech'] and not btn['navigation_type'] and \
                   not (btn.get('functions') and 'GOTO-HOME' in btn['functions']):
                    import re
                    speech = btn['speech']
                    nav_target = None
                    clean_speech = speech
                    
                    # Helper function to find page by name (with normalization)
                    def find_page_id(name):
                        name_lower = name.strip().lower()
                        # Try exact match
                        if name_lower in page_name_to_id:
                            return page_name_to_id[name_lower]
                        # Try with "0 " prefix
                        with_prefix = f"0 {name_lower}"
                        if with_prefix in page_name_to_id:
                            return page_name_to_id[with_prefix]
                        # Try fuzzy match (ignore trailing spaces/punctuation)
                        for page_name, page_id_item in page_name_to_id.items():
                            if page_name.strip().lower() == name_lower:
                                return page_id_item
                            if page_name.strip().lower() == with_prefix.strip():
                                return page_id_item
                        return None
                    
                    # Pattern 1a: (page_name) or (page_name at the end
                    match = re.search(r'\(([^)]+)\)\s*[A-Z+\-,;:/]*\s*$', speech)
                    if not match:
                        # Pattern 1b: incomplete parenthesis at the end
                        match = re.search(r'\(([^()]+)\s*$', speech)
                    if not match:
                        # Pattern 1c: word(s) followed by opening paren at end (e.g., "feelings(")
                        match = re.search(r'\s+([a-z\s]+)\($', speech)
                    
                    if match:
                        nav_target = find_page_id(match.group(1))
                        if nav_target:
                            # Remove the navigation marker from speech
                            clean_speech = speech[:match.start()].strip()
                    
                    # Pattern 2: "0 page_name" at the end or as entire speech
                    if not nav_target:
                        match = re.search(r'\b0\s+([^.!?]+?)(?:\s*[A-Z+\-,;:/]*)?$', speech)
                        if match:
                            nav_target = find_page_id(match.group(1))
                            if nav_target:
                                # If speech is just "0 page_name", clear it
                                if speech.strip().startswith('0 '):
                                    prefix_part = speech[:match.start()].strip()
                                    if not prefix_part or prefix_part == '0':
                                        clean_speech = None
                                    else:
                                        clean_speech = prefix_part
                                else:
                                    clean_speech = speech[:match.start()].strip()
                    
                    # Pattern 3: :PageName with trailing punctuation (e.g., ":WP- Clothes,")
                    if not nav_target and speech.startswith(':'):
                        # Remove leading colon and trailing punctuation
                        content = speech[1:].rstrip(',;:/+')
                        nav_target = find_page_id(content)
                        if nav_target:
                            clean_speech = None
                    
                    # Pattern 4: :text followed by page_name (space-separated)
                    if not nav_target and speech.startswith(':'):
                        # Try to find page name at the end
                        parts = speech[1:].split()
                        if len(parts) > 0:
                            # Check last few words
                            for i in range(len(parts), 0, -1):
                                potential_name = ' '.join(parts[i-1:])
                                nav_target = find_page_id(potential_name)
                                if nav_target:
                                    # Keep the text before the page name
                                    clean_speech = ' '.join(parts[:i-1]).strip()
                                    if not clean_speech:
                                        clean_speech = None
                                    break
                    
                    # Pattern 5: page_name with trailing lowercase letter marker (e.g., "word powerz", "0 don't m")
                    # The trailing letter is a navigation marker, not part of the actual text
                    if not nav_target and len(speech) > 1:
                        # Try removing the last character if it's a single lowercase letter
                        # Check if removing it gives us a valid page name
                        potential_name = speech[:-1].strip()
                        if potential_name:  # Make sure there's something left
                            nav_target = find_page_id(potential_name)
                            if nav_target:
                                clean_speech = None
                    
                    # Pattern 6: "text... page_name[digit]" - navigation target at end with trailing digit/letter
                    # (e.g., "I want to spell my message, ok? 84 KEYBOARD SCAN7")
                    if not nav_target and ' ' in speech:
                        # Look for pattern: sentence ending with space + potential page name + optional trailing char
                        words = speech.split()
                        # Try last 2-5 words as potential page name (with optional trailing char)
                        for word_count in range(5, 1, -1):
                            if len(words) >= word_count:
                                potential_with_marker = ' '.join(words[-word_count:])
                                # Try with and without last character
                                for name_to_try in [potential_with_marker, potential_with_marker[:-1]]:
                                    test_target = find_page_id(name_to_try)
                                    if test_target:
                                        nav_target = test_target
                                        # Clean speech is everything before the navigation
                                        clean_speech = ' '.join(words[:-word_count]).strip()
                                        if not clean_speech:
                                            clean_speech = None
                                        break
                                if nav_target:
                                    break
                    
                    if nav_target:
                        btn['navigation_type'] = 'PERMANENT'
                        btn['navigation_target'] = nav_target
                        btn['speech'] = clean_speech
                
                # Fix navigation targets (convert page names to IDs)
                if btn['navigation_target'] and btn['navigation_target'] not in self.pages:
                    # Try to find page ID from name
                    # Remove common junk patterns: \r, \n, control characters
                    target_clean = btn['navigation_target'].replace('\r', '').replace('\n', '').split(')')[0].strip()
                    # Remove non-printable characters
                    target_clean = ''.join(c for c in target_clean if c.isprintable() or c == ' ')
                    # Try removing trailing gibberish (single or two letters at end)
                    if ' ' in target_clean:
                        parts = target_clean.split()
                        # If last part is 1-2 letters and not a known word, remove it
                        if len(parts) > 1 and len(parts[-1]) <= 2:
                            potential_clean = ' '.join(parts[:-1])
                            if potential_clean.lower() in page_name_to_id:
                                target_clean = potential_clean
                    
                    target_clean_lower = target_clean.lower()
                    if target_clean_lower in page_name_to_id:
                        btn['navigation_target'] = page_name_to_id[target_clean_lower]
