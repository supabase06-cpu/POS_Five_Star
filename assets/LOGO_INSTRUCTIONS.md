# Logo Setup Instructions

## Current Status
The application is configured to work without a logo. Invoices will print with text-only headers.

## To Add Your Company Logo

### Step 1: Prepare Your Logo
1. **Convert to PNG**: Save your logo as a PNG file
2. **Make it Black & White**: Use image editing software to convert to pure black and white (no grayscale)
3. **Resize**: Make it 380-400 pixels wide (height will adjust automatically)
4. **Name**: Save the file as `logo.png`

### Step 2: Add to Project
1. Place the `logo.png` file in the `assets/` directory
2. Open `pubspec.yaml`
3. Uncomment the line: `# - assets/logo.png` (remove the # and space)
4. Run `flutter pub get`
5. Restart the application

### Step 3: Test
1. Go to Printer Settings
2. Use "Send Test Print" to verify the logo appears correctly
3. Process a test transaction to see the logo on invoices

## Using the Existing SVG Logo

If you want to use the existing `LOGO.svg` file:

1. **Convert SVG to PNG**:
   - Open the `LOGO.svg` file in an image editor (like GIMP, Photoshop, or online converter)
   - Export/Save as PNG
   - Set width to 400 pixels
   - Convert to black and white
   - Save as `assets/logo.png`

2. **Follow Step 2 and 3 above**

## Why PNG Instead of SVG?

Thermal printers work best with raster images (PNG) rather than vector graphics (SVG). The PNG format ensures:
- Consistent rendering across different printers
- Faster processing and printing
- Better compatibility with thermal printer drivers
- Optimal quality on thermal paper

## Troubleshooting

- **Logo too large**: Resize to 400px width maximum
- **Logo appears blurry**: Ensure it's saved as black and white, not grayscale
- **Logo doesn't appear**: Check that the file is named exactly `logo.png` and is in the `assets/` directory
- **Build errors**: Make sure the asset is properly listed in `pubspec.yaml`