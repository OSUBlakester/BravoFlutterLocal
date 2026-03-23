# 🎨 HEX to 32-bit ARGB Converter Guide

## Quick Reference

### The Magic Formula
```
ARGB = 4278190080 + HEX_as_decimal
```

Where:
- `4278190080` = Full alpha channel (0xFF000000)
- `HEX_as_decimal` = Your 6-digit hex color converted to decimal

## Step-by-Step Process

### Example: #002244 (Denver Blue)

1. **Remove #**: `002244`
2. **Convert HEX to decimal**: `002244` → `8772`
3. **Add alpha channel**: `4278190080 + 8772 = 4278198852`
4. **Use in Flutter**: `Color(4278198852)`

## Common Colors for Reference

| Color Name | HEX | RGB Decimal | ARGB Decimal |
|------------|-----|-------------|--------------|
| Denver Blue | #002244 | 8772 | 4278198852 |
| White | #FFFFFF | 16777215 | 4294967295 |
| Black | #000000 | 0 | 4278190080 |
| Red | #FF0000 | 16711680 | 4294901760 |
| Green | #00FF00 | 65280 | 4278255360 |
| Blue | #0000FF | 255 | 4278190335 |

## Quick Converter (Python)

```python
def hex_to_argb(hex_color):
    """Convert hex color to 32-bit ARGB for Flutter"""
    hex_color = hex_color.lstrip('#')
    return 4278190080 + int(hex_color, 16)

# Usage
argb_value = hex_to_argb("002244")
print(f"Color(${argb_value})")  # Color(4278198852)
```

## Why This Works

Flutter's `Color()` constructor expects a 32-bit integer with this format:
- **Bits 24-31**: Alpha channel (0xFF = fully opaque)
- **Bits 16-23**: Red channel
- **Bits 8-15**: Green channel  
- **Bits 0-7**: Blue channel

Your 6-digit hex color only has RGB (24 bits), so we add the alpha channel (8 bits) to make it 32 bits.

## Verification

To verify your conversion is correct:
```python
argb = 4278198852
a = (argb >> 24) & 0xFF  # Should be 255 (FF)
r = (argb >> 16) & 0xFF  # Should be 0 (00)
g = (argb >> 8) & 0xFF   # Should be 34 (22)
b = argb & 0xFF          # Should be 68 (44)
print(f"#{r:02X}{g:02X}{b:02X}")  # Should print #002244
```
