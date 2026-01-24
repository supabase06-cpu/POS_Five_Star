import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ImageHelper {
  final ImagePicker _picker = ImagePicker();

  /// Pick image from gallery and crop it
  Future<ImageResult?> pickAndCropImage(BuildContext context) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );

      if (pickedFile == null) return null;

      final bytes = await pickedFile.readAsBytes();
      
      if (!context.mounted) return null;

      // Show crop dialog
      final croppedBytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ImageCropDialog(imageBytes: bytes),
      );

      if (croppedBytes == null) return null;

      return ImageResult(
        bytes: croppedBytes,
        fileName: pickedFile.name,
      );
    } catch (e) {
      debugPrint('❌ Error picking/cropping image: $e');
      return null;
    }
  }
}

class ImageResult {
  final Uint8List bytes;
  final String fileName;

  ImageResult({
    required this.bytes,
    required this.fileName,
  });
}

class ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const ImageCropDialog({super.key, required this.imageBytes});

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  final TransformationController _transformController = TransformationController();
  final GlobalKey _imageKey = GlobalKey();
  
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  Size? _imageSize;
  bool _isProcessing = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _scale = (_scale * details.scale).clamp(0.5, 4.0);
      _offset += details.focalPointDelta;
    });
  }

  void _resetTransform() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  void _zoomIn() {
    setState(() {
      _scale = (_scale * 1.2).clamp(0.5, 4.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _scale = (_scale / 1.2).clamp(0.5, 4.0);
    });
  }

  Future<void> _cropAndSave() async {
    setState(() => _isProcessing = true);

    try {
      // Decode the image
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // Get crop area size (square)
      const cropSize = 280.0;
      
      // Calculate the visible area in image coordinates
      final imageWidth = image.width.toDouble();
      final imageHeight = image.height.toDouble();
      
      // Calculate scale to fit image in view
      final viewScale = cropSize / (imageWidth > imageHeight ? imageWidth : imageHeight);
      final scaledWidth = imageWidth * viewScale * _scale;
      final scaledHeight = imageHeight * viewScale * _scale;
      
      // Calculate crop rectangle in image coordinates
      final centerX = imageWidth / 2;
      final centerY = imageHeight / 2;
      
      final cropWidthInImage = (cropSize / (_scale * viewScale));
      final cropHeightInImage = (cropSize / (_scale * viewScale));
      
      final offsetXInImage = -_offset.dx / (_scale * viewScale);
      final offsetYInImage = -_offset.dy / (_scale * viewScale);
      
      var left = centerX - cropWidthInImage / 2 + offsetXInImage;
      var top = centerY - cropHeightInImage / 2 + offsetYInImage;
      
      // Clamp to image bounds
      left = left.clamp(0, imageWidth - cropWidthInImage);
      top = top.clamp(0, imageHeight - cropHeightInImage);
      
      final cropRect = Rect.fromLTWH(
        left,
        top,
        cropWidthInImage.clamp(1, imageWidth - left),
        cropHeightInImage.clamp(1, imageHeight - top),
      );

      // Create cropped image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      const outputSize = 400.0;
      
      canvas.drawImageRect(
        image,
        cropRect,
        Rect.fromLTWH(0, 0, outputSize, outputSize),
        Paint()..filterQuality = FilterQuality.high,
      );

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(outputSize.toInt(), outputSize.toInt());
      final byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null && mounted) {
        Navigator.of(context).pop(byteData.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint('❌ Error cropping image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to crop image: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450, maxHeight: 550),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Expanded(child: _buildCropArea()),
            _buildControls(),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[900],
      child: Row(
        children: [
          const Icon(Icons.crop, color: Colors.white),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Crop Image',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildCropArea() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Image with gestures
            GestureDetector(
              onScaleUpdate: _onScaleUpdate,
              child: ClipRect(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(_offset.dx, _offset.dy)
                    ..scale(_scale),
                  alignment: Alignment.center,
                  child: Image.memory(
                    widget.imageBytes,
                    key: _imageKey,
                    fit: BoxFit.contain,
                    width: 280,
                    height: 280,
                  ),
                ),
              ),
            ),
            // Crop overlay
            IgnorePointer(
              child: CustomPaint(
                size: const Size(320, 320),
                painter: CropOverlayPainter(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.grey[900],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildControlButton(Icons.zoom_out, 'Zoom Out', _zoomOut),
          const SizedBox(width: 16),
          _buildControlButton(Icons.refresh, 'Reset', _resetTransform),
          const SizedBox(width: 16),
          _buildControlButton(Icons.zoom_in, 'Zoom In', _zoomIn),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[900],
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _cropAndSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

class CropOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final cropRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 280,
      height: 280,
    );

    // Draw dark overlay outside crop area
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw crop border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(cropRect, borderPaint);

    // Draw corner handles
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    const handleLength = 20.0;
    
    // Top-left
    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(handleLength, 0), handlePaint);
    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(0, handleLength), handlePaint);
    
    // Top-right
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(-handleLength, 0), handlePaint);
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(0, handleLength), handlePaint);
    
    // Bottom-left
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(handleLength, 0), handlePaint);
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(0, -handleLength), handlePaint);
    
    // Bottom-right
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(-handleLength, 0), handlePaint);
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(0, -handleLength), handlePaint);

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final thirdWidth = cropRect.width / 3;
    final thirdHeight = cropRect.height / 3;

    // Vertical lines
    canvas.drawLine(
      Offset(cropRect.left + thirdWidth, cropRect.top),
      Offset(cropRect.left + thirdWidth, cropRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left + thirdWidth * 2, cropRect.top),
      Offset(cropRect.left + thirdWidth * 2, cropRect.bottom),
      gridPaint,
    );

    // Horizontal lines
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + thirdHeight),
      Offset(cropRect.right, cropRect.top + thirdHeight),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + thirdHeight * 2),
      Offset(cropRect.right, cropRect.top + thirdHeight * 2),
      gridPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
