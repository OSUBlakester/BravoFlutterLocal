"""
Data Mapping Utility for Accent to Bravo Migration

Converts Accent button and page structures to Bravo's format.
"""

import logging
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


# Icon mapping table: Accent icon names -> Bravo icon identifiers
# TODO: Expand this mapping based on available Bravo icons
ACCENT_TO_BRAVO_ICON_MAP = {
    "HELLO": "wave",
    "GOODBYE": "wave",
    "QUESTION": "question",
    "HELP": "help",
    "YES": "check",
    "NO": "cancel",
    "HAPPY": "happy",
    "SAD": "sad",
    "ANGRY": "angry",
    "FOOD": "food",
    "DRINK": "drink",
    "ANIMALS": "paw",
    "HOME": "home",
    "SCHOOL": "school",
    "PEOPLE": "person",
    "ACTIVITIES": "play",
    # Add more mappings as needed
}


class AccentToBravoMapper:
    """Maps Accent data structures to Bravo format"""
    
    def __init__(self, page_name_map: Optional[Dict[str, str]] = None, parsed_pages: Optional[Dict] = None):
        """
        Initialize the mapper
        
        Args:
            page_name_map: Mapping of Accent page IDs to Bravo page names
                          e.g., {"0201": "watch", "0400": "home"}
            parsed_pages: Full parsed page data for resolving RANDOM-CHOICE references
        """
        self.unmapped_icons = set()
        self.navigation_mappings = page_name_map or {}  # Accent page ID -> Bravo page name
        self.parsed_pages = parsed_pages or {}  # Full page data for RANDOM-CHOICE lookup
    
    def map_button(self, accent_button: Dict, target_bravo_page: Optional[str] = None) -> Dict:
        """
        Convert an Accent button to Bravo button format
        
        Accent button format:
        {
            "page_id": "0400",
            "sequence": 19,
            "row": 1,
            "col": 3,
            "name": "pick up lines",
            "icon": "HELLO",
            "speech": "hi",
            "functions": ["RANDOM-CHOICE(random hi)"],
            "navigation_type": "PERMANENT",
            "navigation_target": "0001"
        }
        
        Bravo button format:
        {
            "row": 1,
            "col": 3,
            "text": "pick up lines",
            "speechPhrase": "hi",
            "targetPage": "pickuplines",
            "LLMQuery": "",
            "queryType": "options",
            "hidden": false
        }
        
        Args:
            accent_button: Button data from Accent
            target_bravo_page: Optional target page name if navigation exists
            
        Returns:
            Bravo-formatted button data
        """
        # Basic mapping
        bravo_button = {
            "row": accent_button.get("row", 0),
            "col": accent_button.get("col", 0),
            "text": accent_button.get("name", ""),
            "speechPhrase": self._map_speech(accent_button),
            "targetPage": self._map_navigation(accent_button, target_bravo_page),
            "navigationType": accent_button.get("navigation_type", ""),
            "LLMQuery": self._map_functions_to_llm(accent_button),
            "queryType": "options",
            "hidden": False
        }
        
        # Track unmapped icons for reporting
        if accent_button.get("icon") and accent_button["icon"] not in ACCENT_TO_BRAVO_ICON_MAP:
            self.unmapped_icons.add(accent_button["icon"])
        
        return bravo_button
    
    def _map_speech(self, accent_button: Dict) -> Optional[str]:
        """
        Map Accent speech to Bravo speechPhrase
        
        Rules:
        - If speech is null -> return None (navigation-only button)
        - If speech is empty string -> return None
        - If RANDOM-CHOICE function exists -> convert to {RANDOM:...} format
        - If speech equals name -> return the speech
        - Otherwise return the speech text
        """
        speech = accent_button.get("speech")
        name = accent_button.get("name", "")
        functions = accent_button.get("functions") or []
        
        # Check for RANDOM-CHOICE function
        for func in functions:
            if func.startswith("RANDOM-CHOICE("):
                # Extract the reference page name
                import re
                match = re.search(r'RANDOM-CHOICE\(([^)]+)\)', func)
                if match:
                    random_page_ref = match.group(1).strip()
                    # Convert RANDOM-CHOICE to {RANDOM:...} format
                    random_options = self._extract_random_options(random_page_ref)
                    if random_options:
                        return f"{{RANDOM:{random_options}}}"
                    else:
                        # Fallback if we couldn't find the page
                        logger.warning(f"Could not resolve RANDOM-CHOICE reference: {random_page_ref}")
                        return speech  # Use original speech if available
        
        if speech is None or speech == "":
            return None
        
        return speech
    
    def _extract_random_options(self, page_ref: str) -> Optional[str]:
        """
        Extract speech options from a RANDOM-CHOICE reference page
        
        Args:
            page_ref: Name or reference to the random choice page (e.g., "random hi")
            
        Returns:
            Pipe-delimited string of options (e.g., "hi|hello|hey")
            or None if page not found
        """
        # Try to find the page by inferred_name (case-insensitive)
        page_ref_lower = page_ref.lower().strip()
        
        for page_id, page_data in self.parsed_pages.items():
            inferred_name = page_data.get("inferred_name", "").lower().strip()
            
            # Match if the inferred name contains the page_ref
            # (e.g., "random hi" matches "0 random hi" or "random hi")
            if inferred_name == page_ref_lower or inferred_name == f"0 {page_ref_lower}":
                # Extract all speech values from buttons on this page
                options = []
                for button in page_data.get("buttons", []):
                    button_speech = button.get("speech")
                    if button_speech and button_speech.strip():
                        # Trim whitespace from ends only
                        options.append(button_speech.strip())
                
                if options:
                    # Join with pipe delimiter
                    return "|".join(options)
                else:
                    logger.warning(f"RANDOM-CHOICE page '{page_ref}' has no speech options")
                    return None
        
        logger.warning(f"RANDOM-CHOICE page reference '{page_ref}' not found in parsed pages")
        return None
    
    def _map_navigation(self, accent_button: Dict, target_page: Optional[str] = None) -> str:
        """
        Map Accent navigation to Bravo targetPage
        
        Args:
            accent_button: Accent button with navigation info
            target_page: Bravo page name to navigate to (if known)
            
        Returns:
            Bravo page name or empty string
        """
        # Check for GOTO-HOME function
        functions = accent_button.get("functions") or []
        if 'GOTO-HOME' in functions:
            return "home"
        
        # Check for GO-BACK-PAGE function
        if 'GO-BACK-PAGE' in functions:
            # GO-BACK-PAGE has no target page - it navigates back in history
            return ""
        
        if not accent_button.get("navigation_target"):
            return ""
        
        # If target page name is provided, use it
        if target_page:
            return target_page
        
        # Try to look up the page name from the mapping
        accent_page_id = accent_button["navigation_target"]
        if accent_page_id in self.navigation_mappings:
            return self.navigation_mappings[accent_page_id]
        
        # Fallback: use the page ID (this will need manual resolution)
        logger.warning(f"No page name mapping found for Accent page {accent_page_id}")
        return f"accent_page_{accent_page_id.lower()}"
    
    def _map_functions_to_llm(self, accent_button: Dict) -> str:
        """
        Map Accent functions (like RANDOM-CHOICE) to Bravo LLMQuery
        
        RANDOM-CHOICE can be approximated with an LLM query that generates
        random responses from a category.
        
        Args:
            accent_button: Accent button with functions
            
        Returns:
            LLM query string or empty string
        """
        functions = accent_button.get("functions") or []
        if not functions:
            return ""
        
        # Handle RANDOM-CHOICE function
        # Note: RANDOM-CHOICE is now converted to {RANDOM:...} format in speechPhrase
        # So we don't need to create an LLM query for it
        for func in functions:
            if func.startswith("RANDOM-CHOICE("):
                # RANDOM-CHOICE is handled via {RANDOM:...} in speechPhrase
                # No LLM query needed
                return ""
        
        return ""
    
    def map_page_metadata(self, accent_page: Dict, bravo_page_name: str) -> Dict:
        """
        Create Bravo page metadata from Accent page
        
        Args:
            accent_page: Accent page data
            bravo_page_name: Desired Bravo page name
            
        Returns:
            Bravo page metadata
        """
        return {
            "name": bravo_page_name,
            "displayName": accent_page.get("inferred_name", bravo_page_name),
            "buttons": []  # Will be populated with mapped buttons
        }
    
    def map_buttons_for_page(self, accent_buttons: List[Dict], 
                            navigation_map: Optional[Dict[str, str]] = None) -> List[Dict]:
        """
        Map all buttons for a page
        
        Args:
            accent_buttons: List of Accent buttons
            navigation_map: Optional mapping of Accent page IDs to Bravo page names
            
        Returns:
            List of Bravo-formatted buttons
        """
        bravo_buttons = []
        
        for accent_button in accent_buttons:
            # Determine target page for navigation
            target_page = None
            nav_target = accent_button.get("navigation_target")
            if nav_target and navigation_map:
                target_page = navigation_map.get(nav_target)
            
            bravo_button = self.map_button(accent_button, target_page)
            bravo_buttons.append(bravo_button)
        
        return bravo_buttons
    
    def map_position(self, accent_row: int, accent_col: int) -> tuple:
        """
        Map button position from Accent grid to Bravo grid
        
        Args:
            accent_row: Row in Accent (0-6)
            accent_col: Column in Accent (0-15)
            
        Returns:
            Tuple of (bravo_row, bravo_col)
        """
        return self.adjust_grid_position(accent_row, accent_col)
    
    def adjust_grid_position(self, accent_row: int, accent_col: int, 
                           bravo_grid_rows: int = 10, bravo_grid_cols: int = 10) -> tuple:
        """
        Adjust button position from Accent grid (7x16) to Bravo grid (10x10)
        
        Args:
            accent_row: Row in Accent (0-6)
            accent_col: Column in Accent (0-15)
            bravo_grid_rows: Bravo grid rows (default 10)
            bravo_grid_cols: Bravo grid columns (default 10)
            
        Returns:
            Tuple of (bravo_row, bravo_col)
        """
        # If button fits within Bravo grid, keep position
        if accent_row < bravo_grid_rows and accent_col < bravo_grid_cols:
            return (accent_row, accent_col)
        
        # Otherwise, map proportionally
        bravo_row = min(int(accent_row * bravo_grid_rows / 7), bravo_grid_rows - 1)
        bravo_col = min(int(accent_col * bravo_grid_cols / 16), bravo_grid_cols - 1)
        
        return (bravo_row, bravo_col)
    
    def create_navigation_mapping(self, accent_pages: Dict[str, Dict], 
                                 existing_bravo_pages: List[str]) -> Dict[str, str]:
        """
        Create a mapping of Accent page IDs to Bravo page names
        
        Args:
            accent_pages: Dictionary of Accent pages (from parsed MTI)
            existing_bravo_pages: List of existing Bravo page names
            
        Returns:
            Dictionary mapping Accent page IDs to Bravo page names
        """
        mapping = {}
        
        for page_id, page_data in accent_pages.items():
            page_name = page_data.get("inferred_name", f"page_{page_id}")
            
            # Convert to Bravo-compatible page name (lowercase, no spaces)
            bravo_name = page_name.lower().replace(' ', '').replace('-', '')
            
            # Remove non-letter characters
            bravo_name = ''.join(c for c in bravo_name if c.isalpha())
            
            # Ensure uniqueness
            original_name = bravo_name
            counter = 1
            while bravo_name in existing_bravo_pages or bravo_name in mapping.values():
                bravo_name = f"{original_name}{counter}"
                counter += 1
            
            mapping[page_id] = bravo_name
        
        return mapping
    
    def get_unmapped_icons(self) -> List[str]:
        """Return list of Accent icons that don't have Bravo mappings"""
        return sorted(list(self.unmapped_icons))
    
    def map_icon(self, accent_icon: Optional[str]) -> Optional[str]:
        """
        Map a single Accent icon to Bravo icon
        
        Args:
            accent_icon: Accent icon name
            
        Returns:
            Bravo icon identifier or None
        """
        if not accent_icon:
            return None
        
        return ACCENT_TO_BRAVO_ICON_MAP.get(accent_icon)


def create_mapper(page_name_map: Optional[Dict[str, str]] = None, parsed_pages: Optional[Dict] = None) -> AccentToBravoMapper:
    """
    Factory function to create a new mapper instance
    
    Args:
        page_name_map: Optional mapping of Accent page IDs to Bravo page names
                      e.g., {"0201": "watch", "0400": "home"}
        parsed_pages: Full parsed page data for resolving RANDOM-CHOICE references
    
    Returns:
        Configured AccentToBravoMapper instance
    """
    return AccentToBravoMapper(page_name_map, parsed_pages)
