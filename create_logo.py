#!/usr/bin/env python3
"""
Simple script to create a PNG logo from the SVG for thermal printing
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_simple_logo():
    # Create a simple black and white logo
    width, height = 400, 400
    
    # Create white background
    img = Image.new('RGB', (width, height), 'white')
    draw = ImageDraw.Draw(img)
    
    # Draw a simple circle with "FSC" text
    circle_radius = 150
    center_x, center_y = width // 2, height // 2
    
    # Draw circle border
    draw.ellipse([center_x - circle_radius, center_y - circle_radius,
                  center_x + circle_radius, center_y + circle_radius], 
                 outline='black', width=8)
    
    # Try to use a font, fallback to default if not available
    try:
        font = ImageFont.truetype("arial.ttf", 80)
    except:
        font = ImageFont.load_default()
    
    # Draw "FSC" text in center
    text = "FSC"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    text_x = center_x - text_width // 2
    text_y = center_y - text_height // 2
    
    draw.text((text_x, text_y), text, fill='black', font=font)
    
    # Save as PNG
    output_path = os.path.join('assets', 'logo.png')
    img.save(output_path, 'PNG')
    print(f"Logo created: {output_path}")
    
    return output_path

if __name__ == "__main__":
    create_simple_logo()